# Tempo

macOS 메뉴바에 상주하는 TODO 앱. 클릭 한 번으로 오늘 할 일을 확인하고, 타이머로 작업 시간을 관리한다.

## 목차

- [설치 방법](#설치-방법)
  - [요구 사항](#요구-사항)
  - [빌드 및 설치](#빌드-및-설치)
  - [업데이트](#업데이트)
- [업데이트 내용](#업데이트-내용)
  - [2026-05-20](#2026-05-20)
  - [2026-05-07](#2026-05-07)
- [사용법](#사용법)
- [주요 기능](#주요-기능)
  - [테스크 관리](#테스크-관리)
  - [날짜 네비게이션](#날짜-네비게이션)
  - [타이머](#타이머)
  - [이월 처리](#이월-처리)
  - [기타](#기타)
- [기술 스택](#기술-스택)
- [프로젝트 구조](#프로젝트-구조)
- [디자인 원칙](#디자인-원칙)

## 설치 방법

### 요구 사항

- macOS 14.0 이상
- Xcode 16 이상
- [xcodegen](https://github.com/yonaskolb/XcodeGen)

### 빌드 및 설치

```bash
# 1. 저장소 클론
git clone git@github.com:reconnectkr/tempo.git
cd tempo

# 2. xcodegen 설치 (최초 1회)
brew install xcodegen

# 3. Xcode 프로젝트 생성
xcodegen generate

# 4. Release 빌드
xcodebuild -project Tempo.xcodeproj -scheme Tempo -configuration Release build

# 5. /Applications에 설치
cp -R ~/Library/Developer/Xcode/DerivedData/Tempo-*/Build/Products/Release/Tempo.app /Applications/

# 6. 실행
open /Applications/Tempo.app
```

메뉴바에 체크마크 아이콘이 나타나면 설치 완료. Dock에는 표시되지 않는다.

### 업데이트

```bash
cd tempo
git pull
xcodegen generate
xcodebuild -project Tempo.xcodeproj -scheme Tempo -configuration Release clean build
pkill -x Tempo
rm -rf /Applications/Tempo.app
cp -R ~/Library/Developer/Xcode/DerivedData/Tempo-*/Build/Products/Release/Tempo.app /Applications/
open /Applications/Tempo.app
```

## 업데이트 내용

### 2026-05-20

#### FOCUS / INPROGRESS / QUEUE / COMPLETED 4영역 구조 도입
- 드롭다운 본문을 4 메인 섹션으로 재편 — 진행 중인 작업이 트리 곳곳에 흩어져 위아래로 스크롤해야 하던 문제 해결
- 같은 작업이 여러 영역에 음영으로 중복 노출되던 패턴 폐기. 한 작업은 정확히 한 곳에만 등장
- **INPROGRESS 우산** 안에 **FOCUS 서브(빨강)** + 일반 진행 중(청록) 구분
- 각 메인 섹션 헤더의 chevron 클릭으로 폴드/펼침 — 폴드된 섹션은 방향키 이동에서도 제외

#### FOCUS와 진행 중 통합
- Cmd+F로 FOCUS에 올리면 status도 자동 `.inProgress`로 전환 — FOCUS와 진행 중 의미를 묶음
- 부모를 FOCUS에 올리면 자손까지 함께 진입·이탈 (자동 동반)
- 작업 완료 시 isFocused 자동 해제
- 자식 단독으로 FOCUS/INPROGRESS에 진입한 경우 `부모 > 자식 >` 출처 경로 라벨을 행 위에 한 번만 노출

#### 같은 부모의 자식 그룹화
- FOCUS·COMPLETED 영역에서 같은 부모의 여러 자식이 흩어진 출처 라벨로 반복되지 않고 그룹당 한 번만 표시
- COMPLETED는 시각 정순을 유지하면서 인접한 같은 트리(부모와 자손)끼리 묶음. 그룹 안에 부모도 들어 있으면 들여쓰기 트리 형태로 노출, 자손만 있으면 부모 경로를 그룹 헤더로 한 번만 표시
- 자식 단독 진입 행은 root 기준 상대 depth(`depthOverride`)로 들여쓰기 reset — 체크박스·텍스트가 다른 행과 정렬됨

#### 진행 중 마커 재설계
- 행 가운데 큰 "IN PROGRESS" 텍스트 워터마크 폐기 — 본문 시야를 가리고 선택 배경과 시각 채널이 충돌
- 행 좌측 엣지에 두꺼운 5px 세로 bar로 교체. 들여쓰기와 무관하게 그려져 본문을 가리지 않음
- 색 우선순위: `isFocused`이면 빨강, 그 외 `inProgress`이면 청록

#### 상세 패널: 상태와 완료일 직접 편집
- 헤더의 읽기 전용 상태 배지를 segmented picker로 교체 — 대기/진행 중/완료 직접 전환
- `TaskService.setStatus`가 완료일 자동 등록, 타이머 정지, FOCUS 해제, 부모 자동 완료 전파를 일관 처리
- 완료일 DatePicker는 항상 노출되고 status가 완료일 때만 활성화 — 미완료 상태에서 입력란이 숨었다 나타나는 깜빡임 제거
- 타이머 실행 중에는 picker 비활성 + 안내 문구

#### COMPLETED 행 메트릭 정렬
- 다른 섹션의 TaskRowView와 동일하게 맞춤: 체크박스 16pt, vertical padding 6pt, 시간 텍스트 monospaced 11pt
- 그룹 헤더가 별도로 그려질 때 행 자체에서는 부모 경로를 생략(`showParentPath` 옵션)

#### 영역 시각 강조 색 체계
| 영역 | 색 |
|------|----|
| FOCUS | red — 짙은 빨강 배경(opacity 0.14) + 좌측 5px 빨강 bar |
| INPROGRESS (우산 + 일반 진행 중 바) | teal — 옅은 청록 배경 + 좌측 5px 청록 bar |
| QUEUE | secondary — 기본 |
| COMPLETED | blue — 옅은 파랑 배경 |

#### 데이터 모델
- `TodoTask`에 `isFocused: Bool`, `focusOrder: Int` 추가 (기본값으로 자동 마이그레이션)
- 완료된 작업은 SwiftData에서 즉시 삭제하지 않고 영구 보존 — 향후 회고 기능을 위한 토대 마련

#### 키보드 단축키 확장
- `Cmd+F` → 선택 작업 FOCUS 토글 (부모면 트리 전체 동반)
- 방향키 ↑/↓은 화면에 보이는 순서(FOCUS → INPROGRESS → QUEUE → COMPLETED) 그대로 순회. 폴드된 섹션은 건너뜀

#### 메뉴바 라벨에 FOCUS 0번째 노출
- 드롭다운을 열지 않고도 지금 집중하는 일을 흘끗 확인 가능
- 표시 규칙
  - FOCUS 0번째(focusOrder 최소 root)가 있으면 그 제목을 메뉴바에 노출. 제목이 길면 18자에서 `…`로 truncate
  - 그 항목의 타이머가 켜져 있으면 제목 뒤에 남은 시간 같이 (`tempo 업데이트  12:34`)
  - FOCUS가 없을 때는 기존 동작 — 가장 빠른 타이머 남은 시간만
  - 둘 다 없으면 체크마크 아이콘만
- 1초 주기로 갱신 (`StatusBarController.updateTimerDisplay`)
- **메뉴바 라벨 폭 적응**
  - FOCUS 0번째가 있을 때만 220pt 고정 — 라벨 내용이 바뀌어도 popover anchor가 흔들리지 않음
  - FOCUS 없을 땐 `variableLength`로 컨텐츠에 맞춰 자동 축소 — 타이머만 있으면 짧은 라벨, 아무것도 없으면 아이콘 폭만
  - 전환 시점(FOCUS 첫 진입 / 마지막 해제)에만 length 한 번 변경. 그 외엔 동일 폭 유지

### 2026-05-07

#### 드래그앤드롭 UX 안정화
- 박스 본체에 드롭하면 자식, 위/아래 가장자리에 드롭하면 형제로 명확히 구분
- 가장자리에서도 X 우측 60%로 끌면 자식으로 승격
- DragGesture를 제목 영역에만 부착해 체크박스/타이머 버튼 우발적 토글 제거
- 드래그 중 행이 커서를 따라 이동(offset/그림자/zIndex)
- drop line이 대상 항목의 depth에 맞춰 들여쓰기, child 모드는 한 단계 더 들여쓴 ghost line 표시
- 트리는 같은 `assignedDate`를 공유하도록 `performDrop`에서 동기화 → 드롭 후 항목이 화면에서 사라지는 버그 제거

#### 진행 중 상태 표시 및 정렬
- 행 가운데에 "진행중" 워터마크(파랑 22pt heavy rounded, opacity 0.22) 표시
- 우클릭 메뉴에 "진행 시작/중지" 추가 — 타이머 없는 항목도 수동 토글 가능
- 진행 중 항목을 포함한 root 트리는 같은 레벨에서 자동으로 위로 정렬, 트리 내부 순서는 유지

#### 입력 UX 개선
- "하위" 라벨 클릭 또는 Tab 키 → 메인 모드로 전환
- 새 항목 추가 시 화면 가운데로 부드럽게 자동 스크롤 (0.35s easeInOut)
- "수정" 라벨 표기 제거(라벨은 항상 메인/하위)

#### 항목 수정·선택·삭제
- 더블 클릭 → 입력창에 해당 항목 내용이 채워져 인라인 수정
- 더블 클릭 시 선택 표시도 해당 항목으로 이동
- 행 선택 후 Backspace로 삭제 (NSEvent local monitor, 입력창 포커스 시 텍스트 편집 우선)

#### 키보드 단축키 확장
- 행 선택 후 Space → 진행/대기 상태 토글 (`TaskService.toggleInProgress`)
- 입력창 포커스 또는 수정 모드일 때는 모든 단축키(Backspace/Space) 비활성

#### 진행 중 워터마크 다듬기
- 한글 "진행중" → 영문 "IN PROGRESS" (18pt heavy rounded + 자간 1.5pt)
- 색상 더 진하게(accent opacity 0.22 → 0.45)로 가독성 향상

#### 부모 자동 완료
- 하위 항목이 모두 완료되면 부모 항목도 자동으로 완료 처리 (`TaskService.propagateCompletionUpward`)
- 루트까지 재귀 전파 — 손자 → 자식 → 부모 → 조부모 순으로 연쇄 완료 가능
- 자동 완료된 부모는 `completedAt` 갱신, 타이머 정지. Glass 사운드는 사용자가 완료한 항목만 재생
- 자식이 미완료로 되돌아가도 부모 상태는 유지 (사용자가 수동 토글 시까지)
#### 키보드 네비게이션 강화
- ↑ / ↓ → 모든 행(루트 + 하위) 사이를 순환 이동, 양 끝에서 감싸짐
- ← / → → 루트(메인) 항목 사이만 이동, 양 끝에서 순환
- 선택 없을 때 ↓ → 첫 루트 / ↑ → 마지막 루트
- Enter → 선택 항목 완료/미완료 토글 (`TaskService.toggleComplete`)
- 입력창 포커스 또는 수정 모드일 때는 모든 단축키(방향키/Backspace/Space/Enter) 비활성 — 텍스트 커서 이동·편집 우선

#### 개발 편의
- `scripts/reload.sh` 추가 — 빌드 + 기존 인스턴스 종료 + 새 빌드 실행을 한 번에 처리 (`TEMPO_CONFIG=Release` 지정 시 Release 빌드)

#### 팝오버 리사이즈
- 우측/하단/우하단 코너에 드래그 핸들 추가 — 가로/세로 독립 조절, 코너로 동시 조절
- 크기는 UserDefaults에 영속화(`popoverWidth`, `popoverHeight`) — 앱 재실행 시 직전 크기 복원
- 최소 320×360 클램프, 최댓값 제한 없음
- 호버 시 ↔ / ↕ / ✛ 커서로 변경, 드래그 중에도 유지
- `AppSettings.shared` Combine 구독으로 `NSPopover.contentSize` 실시간 갱신

#### 드래그앤드롭 사라짐 버그 해결
- **stale row frame 누적 버그 수정** — 날짜 전환·삭제로 화면에서 빠진 행의 frame이 누적돼 드롭 hit-test에 끼어들면서 보이지 않는 다른 날짜 트리로 항목이 흡수되던 현상 제거. `DragState.replaceFrames(_:)` 추가, 매 preference 갱신 시 완전 교체.
- **자식 모드 자동 분류 제거** — 행 가운데 50% = 자식 디폴트 폐기. 우측 절반(relX > 0.5)에서만 `.child` 모드 발동. 제자리에 두려는 의도가 의도치 않게 자식으로 빨려들어가는 일 차단.
- **드롭이 assignedDate를 건드리지 않음** — `performDrop`은 트리 구조(부모/순서/깊이)만 변경. 부모-자식이 다른 날짜를 가질 수 있도록 허용.
- **드롭 후 자동 스크롤 + 1.5s 노란 하이라이트** — 이동한 항목으로 즉시 스크롤하고 배경 강조. 들여쓰기가 깊어진 자식이 돼도 시각적으로 추적 가능.

#### 부모 자동 완료 시 자식 cascade 알림 정리
- `TaskService.deleteTask`가 SwiftData `@Relationship(.cascade)`에 추가로 자식 트리 알림 큐도 명시적 재귀 취소(`cancelNotificationsRecursively`).

#### 날짜 표시 로직 변경 — 트리 일부만 노출
- 기존: 루트의 assignedDate가 selectedDate면 트리 전체 노출.
- 변경: assignedDate가 selectedDate인 task + 그 직속 조상 체인만 노출. 같은 부모의 다른 날짜 자식은 숨김.
- 부모-자식이 서로 다른 날짜를 가질 수 있는 모델로 전환. 컨텍스트(상위 트리)는 보이고, 다른 날짜의 형제 자식은 시야에서 가려짐.
- `MenuContentView.relevantTaskIds`가 직속 조상까지 포함한 노출 대상을 계산.

#### 항목 날짜 이동 + 컨텍스트 메뉴 확장
- 우클릭 메뉴 전면 개편: 수정(⌘E) · 완료 토글(⏎) · 진행 토글(Space) · 시간 변경 · 이전날로(⌘←) / 다음날로(⌘→) · 삭제(⌫)
- ⌘← / ⌘→ — 선택 항목을 이전/다음 날짜로 이동 (`TaskService.moveByDays`)
  - 메인 항목 이동 시 자식 트리 전체 동반
  - 자식만 이동 시 해당 서브트리만 이동, 다음날 화면에는 부모가 컨텍스트로 자동 노출
  - `originalDate`도 함께 이동 → 의도적 재계획이라 "O-N" 배지 안 붙음 (자동 carry-over와 구분)
- 기존 ←/→ 루트 이동과 충돌하지 않도록 modifier 검사 추가

#### 수정 모드 UX 개선
- 입력창 라벨이 수정 중에 "메인/하위" → "수정 중"으로 바뀌어 모드 명시
- 수정 중 ESC → 팝오버 닫지 않고 수정만 취소
- 수정 중 다른 항목 클릭 → 수정 자동 해제
- 수정 취소 시 입력 텍스트/분 필드 초기화
#### Undo / Redo 지원
- `ModelContext.undoManager`를 활성화 — 삭제/이동/수정/완료 토글 등 모든 SwiftData 변경이 ⌘Z로 되돌려짐
- ⌘⇧Z로 다시 실행
- 입력창 포커스 또는 수정 중에는 텍스트 자체 undo가 우선이라 우리 핸들러 비활성
- UndoManager 스택은 메모리에 있으므로 앱 종료 시 초기화. 재실행 후엔 되돌릴 수 없음
- 한계: 알림(NotificationManager) 등 SwiftData 바깥 자원은 undo 추적 안 됨 — 삭제 후 ⌘Z로 항목은 복구되지만 예약돼 있던 타이머 알림은 다시 살아나지 않음

## 사용법

| 동작 | 방법 |
|------|------|
| 드롭다운 열기 | 메뉴바 체크마크 아이콘 좌클릭 |
| About / 종료 | 메뉴바 아이콘 우클릭 |
| 메인 테스크 추가 | 하단 입력창에 입력 후 Enter |
| 하위 테스크 추가 | 테스크 클릭(선택) 후 입력 |
| 선택 해제 | ESC 또는 빈 영역 클릭 |
| 행 선택 이동 | ↑ / ↓ (모든 행, 양 끝 순환) |
| 루트 항목 이동 | ← / → (메인 항목만, 양 끝 순환) |
| 테스크 완료 토글 | 좌측 체크박스 클릭 또는 선택 후 Enter |
| 진행/대기 토글 | 선택 후 Space 또는 우클릭 > 진행 시작/중지 |
| FOCUS 토글 | 선택 후 ⌘F (우클릭 > 포커스에 올리기/내리기) — 부모면 트리 전체 동반 |
| 섹션 폴드 | 각 메인 섹션 헤더 chevron 클릭 |
| 테스크 수정 | 행 더블 클릭 또는 선택 후 ⌘E (우클릭 > 수정) |
| 테스크 삭제 | 선택 후 Backspace 또는 우클릭 > 삭제 |
| 항목 이전날로 이동 | 선택 후 ⌘← (우클릭 > 이전날로 넘기기) |
| 항목 다음날로 이동 | 선택 후 ⌘→ (우클릭 > 다음날로 넘기기) |
| 수정 취소 | 수정 중 ESC (팝오버는 닫히지 않음) |
| 되돌리기 / 다시 실행 | ⌘Z / ⌘⇧Z (앱 실행 중에만 유효) |
| 순서/계층 변경 | 드래그앤드롭 |
| 날짜 이동 | 헤더의 좌/우 화살표 |
| 날짜 선택 | 헤더의 날짜 텍스트 클릭 > 캘린더 |
| 타이머 시작 | 테스크 우측 재생 버튼 |
| 시간 설정 | 테스크 추가 시 "분" 필드에 입력 |
| 팝오버 닫기 | ESC |
| 팝오버 크기 조절 | 우측/하단 가장자리 또는 우하단 코너 드래그 (크기 자동 저장) |

## 주요 기능

### 테스크 관리
- 3단계 계층 구조 (메인 > 하위 1 > 하위 2)
- 드래그앤드롭으로 순서 변경 및 부모 이동
- 우클릭 메뉴로 수정/삭제
- 완료 시 Glass 사운드 재생

### 날짜 네비게이션
- 좌/우 화살표로 이전/다음 날짜 이동
- 커스텀 캘린더에 날짜별 테스크 수 표시
- 주말(토/일) 빨간색 표시
- 과거/미래 날짜에도 테스크 추가 가능

### 타이머
- 테스크별 목표 작업 시간 설정 (분 단위)
- 여러 타이머 동시 실행
- 메뉴바에 가장 빨리 끝나는 타이머의 남은 시간 표시
- 타이머 종료 시 시스템 알림 (+5분, +15분, 완료 액션)

### 이월 처리
- 자정 후 첫 실행 시, 미완료 테스크에 대해 이월 결정 요청
- "오늘로 가져오기" 또는 "완료 처리" 선택
- 모든 결정 완료 전까지 일반 화면 진입 불가

### 기타
- 로그인 시 자동 실행 옵션 (About 윈도우에서 설정)
- 메뉴바 아이콘 우클릭으로 About/종료

## 기술 스택

| 항목 | 선택 |
|------|------|
| 플랫폼 | macOS 14.0+ |
| 언어 | Swift 5.9+ |
| UI | SwiftUI + NSStatusItem |
| 영속화 | SwiftData |
| 알림 | UserNotifications |
| 자동 실행 | ServiceManagement |

## 프로젝트 구조

```
Tempo/
├── TempoApp.swift                # 앱 진입점, AppDelegate
├── Models/
│   └── TodoTask.swift             # SwiftData 모델
├── Services/
│   ├── StatusBarController.swift  # 메뉴바 아이콘, 팝오버, 우클릭 메뉴
│   ├── TaskService.swift          # 테스크 CRUD, 타이머, 이월, 드롭
│   ├── NotificationManager.swift  # 시스템 알림 및 액션 핸들링
│   ├── TimerManager.swift         # 타이머 포맷팅
│   └── DragState.swift            # 드래그앤드롭 상태 관리
├── Views/
│   ├── MenuContentView.swift      # 메인 패널 뷰
│   ├── HeaderView.swift           # 헤더 (앱 이름 + 날짜 네비게이션)
│   ├── TaskRowView.swift          # 테스크 행
│   ├── TaskInputView.swift        # 하단 입력창 (생성/수정)
│   ├── CalendarPickerView.swift   # 커스텀 캘린더
│   ├── CarryOverView.swift        # 이월 결정 UI
│   ├── AboutView.swift            # About 윈도우
│   └── MenuBarLabel.swift         # (레거시, 미사용)
```

## 디자인 원칙

- SF Symbols 사용 (이모지 금지)
- 시스템 시맨틱 컬러 (다크/라이트 자동 대응)
- 시스템 폰트 (SF Pro)
- 그라디언트 배경 금지
- Things 3, Linear, Fantastical 같은 네이티브 macOS 앱 미감 추구
