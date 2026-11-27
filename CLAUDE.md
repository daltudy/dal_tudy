# 달쌤 수능 영단어 (dal_tudy) — 작업 인수인계

이 저장소에서 작업하는 Claude가 먼저 읽는 문서예요. 공개 저장소라 비밀 정보는 넣지 않아요.

## 사용자와 일하는 방식
- 사용자는 '달쌤'(수능 수학 강사). '주인님'이라 부르고 반말로, 차분하고 따뜻한 톤.
- 기능을 바꾸기 전에 계획을 먼저 보여 주고 확인을 받은 뒤 구현한다. (사용자가 명시적으로 요청한 규칙)
- 고친 뒤에는 반드시 로컬 테스트를 돌리고, 결과를 짧게 보고한다.

## 서비스 구성
- 학생용: https://daltudy.github.io/dal_tudy/ (`index.html`)
- 관리자: https://daltudy.github.io/dal_tudy/admin.html (`admin.html`, 관리자 비밀번호는 서버에 해시로 저장)
- 호스팅: GitHub Pages (main 브랜치 / root). 푸시하면 1~2분 뒤 반영.
- 서버: Supabase 무료 플랜, 프로젝트 ref `omojivcwewuajehoyhir` (도쿄 리전). 연결 정보는 `config.js` (publishable 키, 공개돼도 되는 키).
- `setup.sql`: 테이블·함수 정의. Supabase SQL Editor에서 이미 실행됨. 바꿀 땐 사용자에게 SQL을 주고 실행을 부탁해야 함.
- `.github/workflows/keepalive.yml`: 3일마다 `ping` RPC 호출 + `.keepalive` 커밋 (무료 플랜 일시 정지, 예약 작업 60일 비활성화 방지). keepalive 커밋이 쌓이므로 작업 전 `git pull --rebase`.
- `.github/workflows/server-test.yml` + `tests/server-test.mjs`: `config.js`나 `tests/**` 변경 시 실제 서버를 대상으로 테스트. 작업 환경에서는 supabase.co 접속이 막혀 있어서, 실서버 확인은 이 워크플로 로그로 한다 (`gh run list/view -R daltudy/dal_tudy`).

## 서버 (setup.sql)
- `students(name pk, pin_hash, data jsonb, rev, fails, locked_until, ...)`, `app_admin(pw_hash)`. RLS 켜짐, anon 직접 접근 차단.
- RPC: `st_login(p_name,p_pin,p_create)`, `st_save(p_name,p_pin,p_data,p_rev)` (rev 불일치 시 `conflict`+서버 데이터 반환), `ping()`, `admin_setup/admin_status/admin_list/admin_reset_pin/admin_delete`.
- 비밀번호 10회 오류 시 10분 잠금. 내부 함수 `_st_check`, `_admin_ok`는 anon 실행 불가.

## 단어 데이터 (data.json)
- `{w:[[영단어, 뜻, 한글발음, 예문, 예문해석, 주의(없으면 "")], ...], d:[각 Day 시작 인덱스]}`
- 3,662개 = 기존 수능 2000 단어장(중복 합쳐 1,975) + Word Master 색인 1,687(파생어 포함). 120 Day, Day당 30~33개.
- 파생어 묶음(같은 단어 가족)은 같은 Day에 오도록 묶어서 고정 시드로 섞음. 모든 학생이 같은 Day 구성.
- 뜻·예문·주의는 Claude가 작성. 발음은 eng_to_ipa → 한글 변환 규칙으로 자동 생성(일부 수동).
- 데이터 순서를 바꾸면 학생 기록(단어 인덱스 기준)이 꼬이므로 단어 추가는 맨 뒤에만, 기존 인덱스는 절대 바꾸지 않기.

## 학생 앱 동작 (index.html)
- 로그인: 이름 + 숫자 4자리. 없는 이름이면 확인 후 생성. localStorage 키 `daltudy:v1`에 캐시, 변경 400ms 뒤 서버 저장, 창 닫힘/숨김 시 keepalive fetch, 오프라인이면 재시도. 충돌 시 `mergeP`로 병합 후 재저장.
- 프로필 데이터: `next`(다음 Day), `srs{idx:{s,due,w,c,last,seen}}`, `log{dayNum:완료수}`, `results{day:{...}}`, `session`(진행 중 Day), `wb{idx:[틀린횟수,날짜]}`(즐겨찾기), `fsession`(즐겨찾기 테스트/Day 재시험).
- 하루 흐름: 외우기 → 테스트(새 단어 + Day 2부터 복습 20). 하루 최대 2 Day, 기준은 기기 시계 자정.
- 망각곡선 간격 [1,1,3,7,14,30]일. 틀리면 단계 0, 다음 날.
- 복습 20개 순서: 복습일 된 틀린 단어 → 즐겨찾기(최대 8, 오래 안 본 순) → 복습일 된 맞힌 단어 → 많이 틀린 단어.
- 채점: 뜻 중 하나와 일치(띄어쓰기·괄호·[대체어] 처리), '몰라' 계열은 오답, '사실 맞았어요'로 정답 처리.
- 즐겨찾기: 틀리면 자동 추가, ☆로 직접 추가/해제, '외웠어요'로 빼기(되돌리기 4초). 시험 화면 단어 위 버튼으로 토글, 사용자가 직접 끄면 오답이어도 다시 안 들어감.
- 즐겨찾기 테스트(10/20/전체), Day 재시험('재시험 보기'), 이어서 하기/새로 시작(확인 받음), 이전 문제 다시 보기(채점 불변).
- 틀린 횟수 보기 페이지, 사용법 페이지, 모든 화면 '← 홈으로'.

## 로컬 테스트 방법
- `/home/claude/dalapp/mock/server.mjs` 같은 목 서버: PGlite(+pgcrypto)에 `setup.sql`을 올리고 `/rest/v1/rpc/*`를 흉내 내며 정적 파일과 테스트용 `config.js`를 서빙(포트 8790). 세션이 바뀌면 다시 만들어야 함.
- Playwright(크롬, 390x844)로 로그인 → Day 풀기 → 다른 컨텍스트 로그인 → 오프라인/충돌 등을 시험.

## 남은 일 / 메모
- 관리자 페이지 제목은 아직 '달터디 관리자' (학생 앱은 '달쌤 수능 영단어'로 변경함). 바꿀지 사용자 답 대기.
- 관리자 화면의 시험용 계정 'zz서버테스트'는 사용자가 지우도록 안내함.
- 무료 플랜은 자동 백업이 없음 → 사용자에게 월 1회 관리자 '전체 기록 내려받기' 권장.
- 예전 claude.ai 아티팩트 버전(로컬 저장 방식)은 더 이상 쓰지 않음. 백업 코드 가져오기 기능은 사용자 요청으로 제거.
- 앞으로의 아이디어: 같은 구조로 다른 과목 추가(Supabase 프로젝트 하나에 과목별로 저장 가능).
