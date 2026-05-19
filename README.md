# AI Usage

Claude · Codex 사용량을 맥북 상단 메뉴 막대에 띄워주는 앱.

CLI에서는 토큰 사용량·한도를 한눈에 보기 어렵습니다. AI Usage는 메뉴 막대에
두 도구의 사용률을 작게 표시하고, 클릭하면 5시간·주간 한도를 자세히 보여줍니다.

<p align="center">
  <img src="screenshot.png" width="340" alt="AI Usage 팝오버">
</p>

## 무엇을 보여주나

- **메뉴 막대** — `C`(Claude) / `X`(Codex) 사용률을 세로 두 줄로 표시.
  80% 이상 주황, 100% 이상 빨강.
- **팝오버**(좌클릭) — 도구별 카드에 **5시간**·**주간** 한도를 막대·%·리셋
  시각과 함께 표시. 아래에 최근 14일 사용량 그래프(막대에 마우스를 올리면
  그날 토큰 수).

## 실시간 한도 — 두 도구 모두

| 도구 | 방법 |
|------|------|
| **Codex** | `codex app-server` 의 `account/rateLimits/read` 를 호출해 계정의 실제 5시간·주간 한도를 가져옴 |
| **Claude** | 앱에 내장된 claude.ai 로그인 세션으로 claude.ai 사용량 API를 호출해 실제 한도를 가져옴 |

둘 다 **계정 단위 실제 수치**라, 어느 기기에서 사용하든 반영됩니다.

## 처음 설정

- **Codex** — 맥북에 Codex(앱 또는 CLI)가 설치·로그인되어 있으면 **자동**으로
  잡힙니다. 따로 할 것이 없습니다.
- **Claude** — 앱을 처음 켜면 claude.ai 로그인 창이 뜹니다. **한 번만** 로그인하면
  세션이 저장되어 이후로는 자동입니다. (Google 로그인이 막히면 "이메일로
  계속하기"를 쓰세요 — 우클릭 메뉴 → "Claude.ai 로그인" 으로 다시 열 수 있습니다.)

## 메뉴 막대 조작

- **좌클릭** — 상세 팝오버 열기
- **우클릭** — 메뉴:
  - 사용량 보기 / 지금 새로고침 / Claude.ai 로그인
  - **메뉴 막대 표시** — 5시간 / 주간 중 무엇을 보일지
  - **표시할 도구** — Claude·Codex 모두 / Claude만 / Codex만
  - 로그인 시 자동 실행 / AI Usage 정보 / 종료

## 빌드 & 실행

전체 Xcode 없이 Swift 툴체인(Command Line Tools)만으로 빌드됩니다.

```sh
cd "Usage App"
./build-app.sh --install          # 빌드 후 /Applications 에 설치
open "/Applications/AI Usage.app"
```

## 갱신 주기

- Codex 한도: 약 10초 · Claude 한도: 약 60초 · 새로고침 버튼: 즉시
- 14일 그래프용 토큰 기록은 로컬 파일(`~/.claude/projects`, `~/.codex/sessions`)
  에서 읽습니다.

## 참고

- 한도 수치는 각 서비스의 API에서 가져오며, 인증은 Codex·claude.ai의 기존
  세션을 그대로 사용합니다. 대화 내용은 읽지 않습니다.
- claude.ai 세션은 이 앱 전용으로 저장되며 브라우저 쿠키는 건드리지 않습니다.
- claude.ai의 비공개 API를 사용하므로, Anthropic이 API를 바꾸면 갱신이 필요할
  수 있습니다.
