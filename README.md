# AI 라이프 코치

캘린더 일정, 운동/식단/체중 기록, 학업 진도, 그리고 그날그날의 맥락(피로도·고민·질문)을
채팅으로 입력하면 Supabase(PostgreSQL + pgvector)에 저장하고, 하이브리드 RAG(정형 SQL 통계 +
벡터 유사도 검색)로 과거 기록을 대조해 개인화된 조언을 주는 단일 파일(`index.html`) 웹앱입니다.

## 구성

- `supabase/schema.sql` — Supabase에 실행할 DB 스키마 (테이블 + pgvector + RPC 함수 + RLS)
- `index.html` — 앱 전체 (Tailwind CSS + Supabase JS + Chart.js, 전부 CDN, 빌드 불필요)

## 설정 방법

### 1. Supabase 프로젝트 준비
1. [supabase.com](https://supabase.com)에서 새 프로젝트 생성
2. 프로젝트 대시보드 → **SQL Editor** → `supabase/schema.sql` 내용 전체 붙여넣기 → 실행
3. 프로젝트 대시보드 → **Settings → API**에서 `Project URL`과 `anon public` key 확인

### 2. LLM API Key 준비
- 채팅/코칭 응답용: OpenAI 또는 Anthropic(Claude) API Key 중 하나
- 벡터 검색(임베딩)용: **OpenAI API Key는 항상 필요**합니다 (pgvector 컬럼이 OpenAI
  `text-embedding-3-small`, 1536차원 기준으로 만들어져 있습니다). Anthropic은 임베딩 API가
  없기 때문에, 채팅 제공자를 Anthropic으로 선택해도 임베딩용 OpenAI Key는 별도로 입력해야 합니다.

### 3. 앱 배포 (GitHub Pages)
1. 이 저장소를 GitHub Pages로 배포 (Settings → Pages → 브랜치 선택 → 루트 `/`)
2. 배포된 URL로 접속 → 스마트폰에서 "홈 화면에 추가"로 독립 앱처럼 사용 가능
3. 로컬 테스트만 할 경우 `index.html`을 브라우저에서 더블클릭해서 바로 열어도 동작합니다.

### 4. 앱 내 설정
1. 우측 상단 ⚙️ 버튼 클릭
2. Supabase URL / anon key 입력
3. 채팅 LLM 제공자 선택(OpenAI/Anthropic) + 모델명 입력 (예: `gpt-4o-mini`, `claude-sonnet-4-5`)
4. OpenAI API Key(임베딩 필수), 필요 시 Anthropic API Key 입력
5. "연결 테스트" → 성공 확인 후 "저장"

모든 키는 **브라우저 localStorage**에만 저장되며, 이 앱 자체는 외부 서버 없이 브라우저에서
Supabase/OpenAI/Anthropic으로 직접 API를 호출하는 구조입니다. anon key와 API key는 사실상
내 DB 전체 권한 및 결제 권한을 가지므로 타인과 공유하거나 공개 저장소 커밋 메시지 등에 남기지 마세요.

## 핵심 동작

- **실시간 동기화**: 모든 데이터는 Supabase 원격 DB에 즉시 저장되고, `postgres_changes`
  Realtime 구독을 통해 다른 탭/기기에서도 자동 반영됩니다 (`schema.sql` 마지막 블록이
  각 테이블을 `supabase_realtime` publication에 등록합니다).
- **선제적 일일 브리핑**: "코치" 탭을 열었을 때 오늘자 코치 메시지가 아직 없으면, 사용자가
  아무것도 입력하지 않아도 AI가 먼저 오늘 일정·목표·최근 기록을 분석해 시간대별 가이드를
  제시합니다. 상단의 "오늘의 브리핑 다시 받기" 버튼으로 언제든 재요청할 수도 있습니다.
- **매크로 대조 분석**: 최근 7일 단백질/탄수화물/지방 합계를 운동 볼륨·체중 추이와 함께
  코칭 컨텍스트에 포함해 "탄수화물 부족 → 오늘 중량 저하 위험" 같은 정밀 피드백이 가능합니다.

## 알려진 제약사항 (설계상 트레이드오프)

- **구글/삼성 캘린더 실시간 연동(OAuth)** 은 포함하지 않았습니다. 정적 단일 HTML 파일 구조에서
  OAuth 클라이언트 시크릿을 안전하게 다루려면 별도 백엔드가 필요하기 때문입니다. 대신
  "일정" 탭에서 캘린더 앱의 일정을 복사해 붙여넣거나 직접 입력하는 방식으로 동일한 효과(오늘
  타임라인을 AI가 맥락으로 활용)를 구현했습니다.
- 채팅에 자연어로 기록을 입력하면 LLM이 JSON으로 구조를 추출해 SQL 테이블에 나누어 저장합니다.
  드물게 LLM이 형식을 벗어난 응답을 하면 자동으로 "구조화 실패 → 전체 텍스트를 맥락 기억(벡터)으로만
  저장"하는 폴백이 동작합니다. 이 경우 "기록" 탭의 수동 입력창을 사용하면 100% 정확하게 저장됩니다.
- API 키가 브라우저에 그대로 노출되는 구조이므로, 개인 전용 사용을 전제로 합니다. 여러 사람과
  같이 쓰는 용도로는 적합하지 않습니다.
