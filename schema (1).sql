-- ============================================================================
-- AI 인생 코치 앱 - Supabase (PostgreSQL + pgvector) 스키마
-- Supabase 대시보드 > SQL Editor 에서 이 파일 전체를 실행하세요.
-- ============================================================================

-- 1) pgvector 확장 활성화
create extension if not exists vector;
create extension if not exists pgcrypto; -- gen_random_uuid() 사용을 위해

-- ============================================================================
-- 2) 목표(Goal) 테이블 : 특정 기간의 목표 (모든 코칭의 대전제)
-- ============================================================================
create table if not exists goals (
  id uuid primary key default gen_random_uuid(),
  title text not null,                 -- 예: "5월 중순까지 벌크업 후 컷팅"
  description text,                    -- 세부 설명/배경
  category text,                       -- fitness / study / lifestyle 등
  start_date date not null default current_date,
  end_date date,
  status text not null default 'active' check (status in ('active','completed','archived')),
  created_at timestamptz not null default now()
);

-- ============================================================================
-- 3) 일정 / 타임라인 테이블 (정형: 시간 슬롯 / 비정형: 자유 텍스트)
-- ============================================================================
create table if not exists daily_schedules (
  id uuid primary key default gen_random_uuid(),
  log_date date not null default current_date,
  event_title text,
  start_time time,
  end_time time,
  event_type text default 'manual' check (event_type in ('calendar_import','manual','todo')),
  raw_timeline_text text,              -- 당일 할 일/타임라인을 대충 적은 자유 텍스트
  created_at timestamptz not null default now()
);
create index if not exists idx_daily_schedules_date on daily_schedules (log_date);

-- ============================================================================
-- 4) 신체 계측치 (체중 등 정형 수치)
-- ============================================================================
create table if not exists body_metrics (
  id uuid primary key default gen_random_uuid(),
  log_date date not null default current_date,
  weight_kg numeric(5,2),
  body_fat_pct numeric(4,2),
  skeletal_muscle_kg numeric(5,2),
  created_at timestamptz not null default now()
);
create index if not exists idx_body_metrics_date on body_metrics (log_date);

-- ============================================================================
-- 5) 운동 기록 (세트/무게/횟수 정형 데이터)
-- ============================================================================
create table if not exists workout_logs (
  id uuid primary key default gen_random_uuid(),
  log_date date not null default current_date,
  exercise_name text not null,
  set_number int,
  weight_kg numeric(6,2),
  reps int,
  rpe numeric(3,1),                    -- 자각적 운동 강도 (선택)
  created_at timestamptz not null default now()
);
create index if not exists idx_workout_logs_date on workout_logs (log_date);

-- ============================================================================
-- 6) 식단 기록 (섭취 칼로리/영양소 정형 데이터)
-- ============================================================================
create table if not exists diet_logs (
  id uuid primary key default gen_random_uuid(),
  log_date date not null default current_date,
  meal_type text,                      -- breakfast/lunch/dinner/snack
  food_name text,
  calories int,
  protein_g numeric(5,1),
  carbs_g numeric(5,1),
  fat_g numeric(5,1),
  created_at timestamptz not null default now()
);
create index if not exists idx_diet_logs_date on diet_logs (log_date);

-- ============================================================================
-- 7) 영양제 섭취 여부
-- ============================================================================
create table if not exists supplement_logs (
  id uuid primary key default gen_random_uuid(),
  log_date date not null default current_date,
  supplement_name text not null,
  taken boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists idx_supplement_logs_date on supplement_logs (log_date);

-- ============================================================================
-- 8) 학업 진도 기록
-- ============================================================================
create table if not exists study_logs (
  id uuid primary key default gen_random_uuid(),
  log_date date not null default current_date,
  subject text,                        -- 예: "운영체제 커널", "선형대수학"
  hours numeric(4,2),
  progress_note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_study_logs_date on study_logs (log_date);

-- ============================================================================
-- 9) 맥락 기억(Context Memory) : 비정형 데이터 + 임베딩 벡터 (하이브리드 RAG 핵심)
--    피로도, 사소한 생각, 학업 고민, 질문, 타임라인 텍스트 등을 저장.
--    Google Gemini text-embedding-004 기준 768차원.
-- ============================================================================
create table if not exists context_memories (
  id uuid primary key default gen_random_uuid(),
  log_date date not null default current_date,
  source_type text not null default 'chat'
    check (source_type in ('chat','timeline','fatigue','thought','study_concern','question')),
  content text not null,
  embedding vector(768),
  created_at timestamptz not null default now()
);

-- 벡터 유사도 검색을 위한 ivfflat 인덱스 (코사인 거리 기준)
create index if not exists idx_context_memories_embedding
  on context_memories using ivfflat (embedding vector_cosine_ops) with (lists = 100);
create index if not exists idx_context_memories_date on context_memories (log_date);

-- ============================================================================
-- 10) 채팅 히스토리 (AI 코치와의 대화 표시용 로그)
-- ============================================================================
create table if not exists chat_history (
  id uuid primary key default gen_random_uuid(),
  role text not null check (role in ('user','assistant')),
  content text not null,
  created_at timestamptz not null default now()
);

-- ============================================================================
-- 11) 벡터 유사도 검색 RPC 함수 (pgvector 코사인 유사도)
--     프론트엔드에서 supabase.rpc('match_context_memories', {...}) 로 호출
-- ============================================================================
create or replace function match_context_memories(
  query_embedding vector(768),
  match_count int default 5,
  filter_date_from date default null
)
returns table (
  id uuid,
  log_date date,
  source_type text,
  content text,
  similarity float
)
language plpgsql
as $$
begin
  return query
  select
    cm.id,
    cm.log_date,
    cm.source_type,
    cm.content,
    1 - (cm.embedding <=> query_embedding) as similarity
  from context_memories cm
  where cm.embedding is not null
    and (filter_date_from is null or cm.log_date >= filter_date_from)
  order by cm.embedding <=> query_embedding
  limit match_count;
end;
$$;

-- ============================================================================
-- 12) RLS (Row Level Security)
--     이 앱은 별도 로그인 없이 브라우저에 저장한 anon key로 개인이 단독 사용하는
--     구조이므로, anon 역할에 대해 전체 CRUD를 허용하는 개방 정책을 건다.
--     주의: anon key를 절대 타인에게 공유하지 마세요. (사실상 이 key = 내 DB 전체 권한)
-- ============================================================================
alter table goals enable row level security;
alter table daily_schedules enable row level security;
alter table body_metrics enable row level security;
alter table workout_logs enable row level security;
alter table diet_logs enable row level security;
alter table supplement_logs enable row level security;
alter table study_logs enable row level security;
alter table context_memories enable row level security;
alter table chat_history enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array[
    'goals','daily_schedules','body_metrics','workout_logs','diet_logs',
    'supplement_logs','study_logs','context_memories','chat_history'
  ]
  loop
    execute format(
      'drop policy if exists "allow_all_anon" on %I;
       create policy "allow_all_anon" on %I for all to anon using (true) with check (true);',
      t, t
    );
  end loop;
end $$;

-- ============================================================================
-- 13) Realtime 동기화
--     "LocalStorage가 아닌 실제 Supabase 원격 DB와 실시간 동기화" 요구사항을 위해
--     각 테이블을 supabase_realtime publication에 등록한다. 이렇게 하면
--     index.html이 postgres_changes 구독을 통해 INSERT/UPDATE/DELETE를
--     다른 기기/탭에서도 즉시 반영받을 수 있다.
--     (Supabase 프로젝트는 기본적으로 'supabase_realtime' publication을 생성해 둔다.)
-- ============================================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'goals','daily_schedules','body_metrics','workout_logs','diet_logs',
    'supplement_logs','study_logs','context_memories','chat_history'
  ]
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ============================================================================
-- 완료. 이후 index.html 의 설정(Settings) 창에서
-- Supabase URL / anon public key 를 입력하면 바로 연동됩니다.
-- ============================================================================
