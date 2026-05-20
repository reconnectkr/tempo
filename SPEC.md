# Tempo — macOS 메뉴바 TODO 앱 명세서

## 0. 이 문서의 목적

이 문서는 **Tempo**라는 macOS 메뉴바 TODO 앱의 구현을 다음 에이전트에게 인계하기 위해 작성되었다. 기획·UX·아키텍처 결정은 모두 완료되었으며, 이 문서는 그 결과물이다. 이 문서만 보고 바로 구현에 착수할 수 있도록 작성하였다.

**모든 결정은 확정되었으며 임의로 변경하지 말 것.** 사양상 모호한 부분이 있다면 사용자에게 확인할 것.

---

## 1. 제품 개요

### 1.1 컨셉

상단 메뉴바에 상주하면서 빠르게 액세스 가능한 TODO 앱. 일반 윈도우 앱은 다른 창에 묻혀 잊혀지는 문제가 있으나, 메뉴바 앱은 항상 시야에 있고 클릭 한 번으로 접근 가능하다.

### 1.2 핵심 가치

- **즉시 접근성** — 메뉴바 클릭 한 번으로 오늘 할 일 확인
- **자연스러운 이월 처리** — 못 끝낸 일을 다음날 자동 사라지지 않게, 사용자에게 의사를 묻는다
- **포모도로식 시간 관리** — 각 테스크에 목표 시간을 설정하고, 시작 버튼을 누르면 시스템 알림으로 종료를 알림

### 1.3 기술 스택

| 항목 | 선택 |
|------|------|
| 플랫폼 | macOS 14.0+ (SwiftData 안정성을 위해) |
| 언어 | Swift 5.9+ |
| UI 프레임워크 | SwiftUI |
| 영속화 | SwiftData |
| IDE | Xcode 16+ |
| 메뉴바 통합 | `MenuBarExtra` (SwiftUI 모던 API) |
| 알림 | `UserNotifications` 프레임워크 |

---

## 2. 기능 명세

### 2.1 테스크 관리

#### 2.1.1 테스크 구조

- **3단계 계층 제한**: 메인 테스크 (depth 0) → 하위 1단계 (depth 1) → 하위 2단계 (depth 2)
- 각 테스크는 제목, 목표 작업 시간, 상태, 할당 날짜를 가진다
- 메인 테스크는 부모가 없으며, 하위 테스크는 반드시 부모를 가진다

#### 2.1.2 테스크 생성

드롭다운 하단에 항상 고정된 입력창이 존재한다. 동작 방식:

1. **기본 상태**: 입력 후 Enter → 메인 테스크로 추가됨
2. **테스크 선택 상태**: 위쪽 리스트에서 특정 테스크를 클릭하여 선택한 후 입력 → 선택된 테스크의 하위로 추가됨
3. **선택 해제**: ESC 키 또는 입력창 아래의 "메인으로 변경" 버튼 클릭

**제약**: depth 2 테스크가 선택된 상태에서는 더 이상 하위 추가 불가. 입력창을 비활성화하거나 안내 메시지 표시.

#### 2.1.3 테스크 완료

- 각 테스크 좌측 체크박스 클릭 → `completed` 상태로 전환
- 완료된 작업은 QUEUE/FOCUS에서 **즉시 사라짐** (0.2초 페이드아웃 후 제거)
- 동시에 COMPLETED 섹션(2.4.5)에 추가됨
- 자정이 지나면 COMPLETED 섹션도 비워짐
- 완료 시 `isFocused`가 자동으로 `false`로 설정됨 (FOCUS 자동 해제)

#### 2.1.4 드래그앤드롭

- 같은 부모 내 형제 순서 변경 가능
- **다른 부모로 이동도 가능** (자유로운 트리 재구성)

**드롭 타겟 영역 (3종)**:
- 행 위쪽 절반: 형제로 위에 삽입
- 행 가운데(들여쓰기 영역): 자식으로 편입
- 행 아래쪽 절반: 형제로 아래에 삽입

**시각적 피드백**:
- 형제 삽입: 가로 라인 표시
- 자식 편입: 행 전체 하이라이트
- 불가능한 드롭: 빨간색 또는 X 표시

**제약 조건**:
1. 자기 자신의 자손에게 드롭 불가 (순환 참조 방지)
2. 드롭 결과가 3단계를 초과하면 불가
3. 드롭 시 자기 자신과 모든 자손의 `depth` 재계산 필요

### 2.2 타이머 기능

#### 2.2.1 시작/일시정지

- 각 테스크 우측에 시작 버튼 (`play.fill`) 표시
- 클릭하면 타이머 시작, 버튼은 일시정지 (`pause.fill`)로 전환되고 남은 시간 표시
- **여러 테스크의 타이머를 동시에 실행 가능** (제한 없음)

#### 2.2.2 메뉴바 표시

- 타이머가 하나도 없을 때: 앱 아이콘만 표시
- 타이머가 1개 이상일 때: **가장 빨리 종료되는 타이머의 남은 시간**만 표시 (예: `12:34`)
- 실행 중인 개수는 표시하지 않음 (드롭다운에서 확인 가능)
- 1초마다 갱신

#### 2.2.3 시간 설정/수정

- 테스크 생성 시 작업 목표 시간 지정
- 드롭다운에서 우클릭 또는 별도 메뉴를 통해 시간 수정 가능

#### 2.2.4 종료 시 동작

- 시스템 알림 (소리 포함)
- 알림에 액션 버튼: `+5분`, `+15분`, `완료`
- `+5분`/`+15분` 클릭 시 타이머 연장
- `완료` 클릭 시 테스크 완료 처리

### 2.3 일자 기반 표시 및 이월

#### 2.3.1 기본 표시

- 드롭다운에는 **오늘 날짜에 할당된 테스크만** 표시
- 자정이 지나면 어제 테스크는 보이지 않음

#### 2.3.2 이월 결정 UI

자정이 지나고 다음날 처음 메뉴바를 열었을 때, 어제 미완료 테스크가 있다면:

1. 일반 드롭다운 대신 **이월 결정 모드**로 진입
2. 미완료 테스크들을 나열하며 각각에 대해 결정을 묻는다
3. 각 테스크마다 두 버튼: `[오늘로 가져오기]`, `[완료 처리]`
4. 하단에 일괄 처리 버튼: `[모두 가져오기]`, `[모두 완료]`
5. **모든 결정이 완료될 때까지 일반 드롭다운으로 진입할 수 없다**
6. 결정 완료 후 자동으로 일반 드롭다운으로 전환

#### 2.3.3 이월 처리 로직

- "오늘로 가져오기" 선택 시:
  - `assignedDate`를 오늘로 변경
  - `carriedOverCount` 1 증가
  - `needsCarryOverDecision`를 `false`로 설정
- "완료 처리" 선택 시:
  - `status`를 `completed`로 변경
  - `completedAt`을 현재 시각으로 기록

#### 2.3.4 며칠째 진행 중인지 표시

- `originalDate`(처음 만들어진 날)와 `assignedDate`(현재 할당일)의 차이로 계산
- 이월 결정 UI에서 "3일째" 형태로 표시
- 일반 드롭다운에서는 일정 일수 이상 (예: 3일 이상) 끌고 있는 테스크에 시각적 신호 (색상 변화 등)를 줄 수 있음

### 2.4 FOCUS / QUEUE / COMPLETED 영역

드롭다운 본문은 세 영역으로 나뉜다. 작업은 항상 이 셋 중 하나에 속한다. 이 구조는 "지금 의식 켜둔 일"과 "아직 손에 안 잡은 일"을 시각적으로 분리하여, 진행중인 작업이 트리 곳곳에 흩어졌을 때 위아래로 스크롤하지 않아도 되게 한다.

#### 2.4.1 영역 정의

**FOCUS** — 지금 의식적으로 집중 중인 작업의 집합. 사용자가 명시로 올린 것만 들어감. 트리 위계 일부 유지(들여쓰기).

**QUEUE** — 아직 손에 잡지 않은 모든 작업. 기존 3단계 트리 그대로. 새 작업 입력의 기본 진입처.

**COMPLETED** — 오늘 완료된 작업. 헤더에 카운터 표시. 기본 접힘.

#### 2.4.2 FOCUS 진입·이탈 규칙

- 작업을 선택한 상태에서 `Cmd+F` → FOCUS 진입/이탈 토글
- **부모 노드를 올리면 자기 자신 + 모든 자손이 함께 진입한다.** 자식만 올리면 그 자식과 그 자손만 진입.
- 부모가 이미 FOCUS인 상태에서 자식을 또 올림 시도하면 no-op (자손은 이미 따라와 있음)
- 작업 완료 시 `isFocused`가 자동으로 `false`로 설정됨
- **타이머 시작·정지와 FOCUS는 완전 독립.** 자동 연동 없음.

#### 2.4.3 FOCUS 표시 방식

- 들여쓰기 트리 유지 (depth 0/1/2 가독성)
- 자식 단독으로 올린 경우 출처 부모 경로를 작은 회색 라벨로 그 위에 붙임 (예: `보고서 작성 >`)
- 표시 기호:
  - `▷` — FOCUS에 있지만 타이머 안 돔
  - `▶` — 타이머 실행 중
  - `pause` — 타이머 일시정지
- FOCUS 내부 정렬: 올린 순서가 기본. 드래그앤드롭으로 수동 재정렬 가능.
- FOCUS 항목 클릭 시 우측 상세 패널이 열림 (QUEUE 클릭과 동일 동작)

#### 2.4.4 QUEUE의 음영 표시

- FOCUS에 올라간 작업은 QUEUE에서도 음영(`◌`)으로 남는다. 위치는 트리 원위치 그대로.
- 부모를 트리째 FOCUS에 올렸으면 그 트리 전체가 음영 처리됨
- 음영 항목도 모든 조작 가능 (체크박스, 우클릭, 드래그). 음영은 시각 표시일 뿐 비활성화 아님.

#### 2.4.5 COMPLETED 섹션 (오늘 모드)

- 체크박스 클릭 시 QUEUE/FOCUS에서 즉시 사라지고 COMPLETED로 이동 (0.2초 페이드아웃)
- 헤더에 카운터 (`COMPLETED (3)`), `[v] / [^]` 토글로 접힘/펼침
- 기본 접힘
- 정렬: 완료 시각 정순 (오래된 게 위)
- 항목 표시: `● {작업명}  {HH:MM}`. 자식 작업이면 `● 보고서 > 자료 수집  09:42`
- 자정이 지나면 비워짐 (오늘 모드에서 안 보임). 데이터 자체는 영구 보존되어 과거 모드에서 조회됨.

#### 2.4.6 단축키

| 키 | 동작 | 조건 |
|----|------|------|
| `Cmd+F` | 선택 작업 FOCUS 토글 (부모면 트리 전체) | 입력창 포커스 아닐 때 |
| `Cmd+F+F` (Cmd 누른 채 F 두 번 연타) | FOCUS 영역으로 스크롤·하이라이트 | 동일 |
| `Space` | FOCUS 항목 타이머 시작/정지 | FOCUS 항목 선택 시 |
| `Cmd+[` | 하루 전(과거) 날짜로 이동 | (2.4.7 과거 모드) |
| `Cmd+]` | 하루 후 날짜로 이동 (오늘까지만) | 동일 |
| `Cmd+T` | 오늘로 복귀 | 동일 |
| `ESC` | 선택 해제 | (기존 SPEC) |

#### 2.4.7 과거 모드 (날짜 네비게이션)

- 헤더의 날짜 좌우에 `◀` / `▶` 화살표. 화살표 클릭 또는 `Cmd+[` / `Cmd+]`로 날짜 이동.
- 오늘이 아닌 날짜로 이동하면 **과거 모드** 진입.
- 과거 모드에선 **FOCUS와 QUEUE 영역이 숨겨진다.** COMPLETED만 표시. 펼친 상태 default.
- 헤더에 `[오늘로]` 버튼 표시. 클릭 또는 `Cmd+T`로 즉시 복귀.
- 미래 날짜(오늘 이후)로는 이동 불가. `▶` 버튼은 오늘에서 비활성.
- 데이터 보존: 완료된 작업은 1차 버전에선 **영구 보존**한다. UI 노출만 과거 모드 펼침으로 제한. 향후 정식 회고 기능 도입 시 활용.
- 과거 모드 입력창은 비활성화 (과거에 새 작업 추가는 의미 모호함).

#### 2.4.8 작업 이동 흐름 요약

```
[새 작업 입력]
      │
      ▼
   QUEUE (○)  ──── Cmd+F ────▶  FOCUS (▷ / ▶)
      ▲                              │
      └─────── Cmd+F (해제) ────────┘
      │
      ▼ (체크박스)
   COMPLETED (●)  ──── 자정 ────▶  과거 모드에서만 조회 가능
```

---

## 3. 데이터 모델

### 3.1 Task 엔티티

```swift
import SwiftData
import Foundation

@Model
final class Task {
    // 식별자
    var id: UUID

    // 컨텐츠
    var title: String
    var createdAt: Date
    var originalDate: Date  // 처음 만들어진 "할당 날짜" (불변)

    // 상태
    var status: TaskStatus
    var completedAt: Date?

    // 날짜 관리
    var assignedDate: Date     // 현재 어느 날의 할 일인지
    var carriedOverCount: Int  // 이월 횟수

    // 계층 구조 (3단계 제한)
    var parent: Task?
    @Relationship(deleteRule: .cascade, inverse: \Task.parent)
    var children: [Task] = []
    var depth: Int       // 0=메인, 1=하위1, 2=하위2
    var sortOrder: Int   // 같은 부모 내 정렬 순서

    // 타이머
    var plannedDuration: TimeInterval?  // 목표 작업 시간 (초)
    var timerStartedAt: Date?            // 시작 버튼 누른 시각
    var timerEndsAt: Date?               // 알림 보낼 시각 (계산값 캐싱)

    // 이월 결정 대기 플래그
    var needsCarryOverDecision: Bool

    // FOCUS 영역 (2.4 참고)
    var isFocused: Bool   // true면 FOCUS 영역에 노출 (+ QUEUE에서는 음영)
    var focusOrder: Int   // FOCUS 내 정렬 순서. isFocused=false면 무의미.

    init(title: String, assignedDate: Date, parent: Task? = nil, sortOrder: Int = 0) {
        let startOfDay = Calendar.current.startOfDay(for: assignedDate)
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.originalDate = startOfDay
        self.status = .pending
        self.assignedDate = startOfDay
        self.carriedOverCount = 0
        self.parent = parent
        self.depth = (parent?.depth ?? -1) + 1
        self.sortOrder = sortOrder
        self.needsCarryOverDecision = false
        self.isFocused = false
        self.focusOrder = 0
    }

    // 며칠째 진행 중인지 (1일째부터 시작)
    var daysActive: Int {
        (Calendar.current.dateComponents([.day], from: originalDate, to: assignedDate).day ?? 0) + 1
    }

    // 타이머 실행 중 여부
    var isTimerRunning: Bool {
        timerStartedAt != nil && status == .inProgress
    }

    // 타이머 남은 시간
    var remainingTime: TimeInterval? {
        guard let endsAt = timerEndsAt else { return nil }
        return max(0, endsAt.timeIntervalSinceNow)
    }
}

enum TaskStatus: String, Codable {
    case pending      // 미시작
    case inProgress   // 타이머 실행 중
    case completed    // 완료
}
```

### 3.2 모델 설계 결정 사항 (변경 금지)

- `originalDate`는 불변. 처음 생성될 때만 설정하고 이월되어도 변경하지 않는다. `daysActive` 계산의 기준점이다.
- `depth`는 캐싱된 값이다. 매번 부모를 거슬러 올라가서 계산하는 대신 저장하여 3단계 제한 검증을 빠르게 한다. **부모 변경 시 반드시 자기 자신과 모든 자손의 depth를 재계산해야 한다.**
- `timerEndsAt`은 `timerStartedAt + plannedDuration`로 계산 가능하지만, "가장 빨리 끝나는 타이머" 쿼리가 빈번하므로 캐싱한다.
- 회고 기능은 1차 버전에서 구현하지 않는다. 따라서 일자별 스냅샷이나 별도 이력 엔티티는 만들지 않는다. 단순 카운트(`carriedOverCount`)만으로 "며칠째 진행 중" 표시를 구현한다.
- `isFocused`는 작업 단위 플래그다. 부모-자식 동시 동반은 별도 엔티티가 아니라 토글 로직(5.5)에서 자손을 재귀로 갱신해 처리한다. 데이터 모델은 평탄하게 유지.
- 완료된 작업(`status == .completed`)은 데이터에서 즉시 삭제되지 않는다. UI에서만 당일 COMPLETED 섹션에 노출되고, 자정 후엔 과거 모드(2.4.7)에서만 조회된다. 영구 보존을 기본으로 한다.

---

## 4. UI 명세

### 4.1 디자인 원칙

- **이모지 사용 금지** — 어디에도 이모지를 쓰지 않는다
- **그라디언트 배경 사용 금지** — 배경은 시스템 머티리얼만 사용
- **AI 답지 않게** — Things 3, Linear, Fantastical과 같은 정통 macOS 네이티브 앱의 미감을 추구한다
- **SF Symbols 사용** — 모든 아이콘은 Apple SF Symbols에서 가져온다 (이모지 대체)
- **시스템 컬러 사용** — `Color.primary`, `Color.secondary`, `Color.accentColor` 등 시스템이 제공하는 시맨틱 컬러를 사용한다. 다크/라이트 모드에 자동 대응된다
- **시스템 폰트** — SF Pro (시스템 기본). 별도 폰트 사용 금지

### 4.2 메뉴바 아이콘

- **타이머 없을 때**: SF Symbol `circle.fill` 또는 앱 전용 단순 아이콘만 표시
- **타이머 있을 때**: 아이콘 + 가장 빨리 끝나는 타이머의 남은 시간 (`MM:SS` 형식)
- 1초마다 텍스트 갱신
- 텍스트는 폭이 너무 넓어지지 않도록 monospaced 숫자 사용 (`.monospacedDigit()`)

### 4.3 드롭다운 — 오늘 모드

레이아웃 (텍스트 와이어프레임):

```
┌─────────────────────────────────────┐
│ Tempo       ◀  2026-05-20 (수)  ▶   │  ← 헤더: 날짜 좌우 화살표
├─────────────────────────────────────┤
│ FOCUS (3)                           │
│  ▷ 보고서 작성                       │  ← 부모 단위로 올림
│      ▷ 자료 수집      pause  12:00  │
│      ▷ 목차 작성                     │
│                                     │
│  보고서 작성 >                       │  ← 자식만 올렸을 때 출처 라벨
│  ▷ 색감 정리          play   3:42   │
│                                     │
│  ▷ 코드 리뷰                         │  ← 단일 depth 0
├─────────────────────────────────────┤
│ QUEUE                               │
│  ◌ 보고서 작성                       │  ← 부모째 음영
│      ◌ 자료 수집                     │
│      ◌ 목차 작성                     │
│  ○ 디자인 검토                       │
│      ◌ 색감 정리                     │  ← 자식만 FOCUS, 부모는 활성
│      ○ 시안 비교                     │
│  ◌ 코드 리뷰                         │
├─────────────────────────────────────┤
│ COMPLETED (2)                  [v]  │  ← 기본 접힘
├─────────────────────────────────────┤
│ [입력...]                       [↵] │  ← 항상 고정된 입력창
└─────────────────────────────────────┘
```

**COMPLETED 펼친 상태**:

```
│ COMPLETED (2)                  [^]  │
│  ● 이메일 정리              10:15   │
│  ● 슬랙 답장                11:32   │
```

**구성 요소 / 표시 기호**:

| 요소 | SF Symbol | 의미 |
|------|-----------|------|
| QUEUE 일반 미완료 | `circle` (○) | 평범한 대기 |
| QUEUE 음영 (FOCUS에 있음) | `circle.dotted` (◌) | 지금 FOCUS에 올라가 있음 |
| FOCUS 의식만 | `triangle` 또는 커스텀 (▷) | 올렸지만 타이머 X |
| FOCUS 타이머 ON | `play.fill` (▶) | 실행 중 |
| FOCUS 타이머 일시정지 | `pause.fill` | 일시정지 |
| COMPLETED 항목 | `checkmark.circle.fill` (●) | 완료됨 |
| 섹션 접힘/펼침 | `chevron.down` / `chevron.up` | 토글 |
| 입력 Enter | `return` 또는 `arrow.turn.down.left` | 추가 |
| 날짜 네비 | `chevron.left` / `chevron.right` | 과거/다음 날짜 |

**들여쓰기** (FOCUS·QUEUE 동일):
- depth 0: 좌측 패딩 0
- depth 1: 좌측 패딩 24pt
- depth 2: 좌측 패딩 48pt

**FOCUS의 자식 출처 라벨**:
- 자식만 단독으로 FOCUS에 올린 경우, 항목 바로 위에 작은 회색 라벨 (`.font(.caption2).foregroundStyle(.secondary)`)로 부모 경로 표시
- 부모를 통째로 올린 경우엔 라벨 없음 (트리 자체가 컨텍스트가 됨)

**선택된 작업**:
- 행 배경에 미세한 강조색 (시스템 selection color)
- 입력창 아래에 "→ '{선택된 작업 제목}'의 하위로 추가" 안내 텍스트 (선택된 게 QUEUE 항목일 때만)

**드롭다운 크기**:
- 너비 360pt 권장 (메뉴바 앱 표준)
- 높이는 컨텐츠에 따라 가변. 많으면 스크롤
- 최소 200pt, 최대 600pt 정도

### 4.3.1 드롭다운 — 과거 모드

```
┌─────────────────────────────────────┐
│ Tempo  ◀ 2026-05-19 (화) ▶  [오늘로]│
├─────────────────────────────────────┤
│ COMPLETED (4)                       │  ← 펼친 상태 default
│  ● 어제 보고서 작성          09:12  │
│  ● 어제 자료 수집            11:48  │
│  ● 어제 이메일 정리          15:30  │
│  ● 어제 코드 리뷰            17:55  │
├─────────────────────────────────────┤
│  (FOCUS·QUEUE 영역 숨김)            │
├─────────────────────────────────────┤
│  (입력창 비활성화)                   │
└─────────────────────────────────────┘
```

- 헤더 우측에 `[오늘로]` 버튼 (오늘이 아닐 때만 노출)
- 빈 날짜로 이동한 경우: `완료된 일이 없습니다` 빈 상태 표시
- 30일 이전이라도 데이터 있으면 보여줌. UI 자체 제한 없음.

### 4.4 드롭다운 — 이월 결정 모드

```
┌─────────────────────────────────────┐
│ Tempo              2026-04-26 (일)  │
├─────────────────────────────────────┤
│  어제 못 끝낸 일이 3개 있어요        │
│                                     │
│  보고서 작성              3일째     │
│  [오늘로 가져오기]  [완료 처리]     │
│                                     │
│  코드 리뷰                1일째     │
│  [오늘로 가져오기]  [완료 처리]     │
│                                     │
│  이메일 정리              2일째     │
│  [오늘로 가져오기]  [완료 처리]     │
│                                     │
├─────────────────────────────────────┤
│  모두 가져오기   |   모두 완료      │
└─────────────────────────────────────┘
```

- 미결정 테스크가 모두 처리될 때까지 이 화면을 유지
- 각 결정 즉시 해당 항목 제거 (애니메이션과 함께)
- 모두 처리되면 일반 드롭다운으로 자동 전환

### 4.5 시스템 알림

타이머 종료 시 macOS 표준 알림:

```
┌────────────────────────────────────┐
│  Tempo                              │
│  "보고서 작성" 시간이 끝났어요      │
│                                    │
│  [+5분]  [+15분]  [완료]            │
└────────────────────────────────────┘
```

- `UNNotificationCategory`에 액션 등록
- 사운드 포함 (시스템 기본 알림 사운드)
- 알림 클릭 시 메뉴바 드롭다운을 자동으로 열어줌 (선택 사항)

---

## 5. 핵심 알고리즘

### 5.1 드래그앤드롭 검증

```swift
enum DropMode {
    case siblingAbove
    case siblingBelow
    case child
}

func canDrop(_ source: Task, onto target: Task, as mode: DropMode) -> Bool {
    // 1. 자기 자신에게 드롭 불가
    if source.id == target.id { return false }

    // 2. 자기 자손에게 드롭 불가 (순환 참조 방지)
    if isDescendant(target, of: source) { return false }

    // 3. depth 검증
    let newParentDepth: Int
    switch mode {
    case .siblingAbove, .siblingBelow:
        newParentDepth = target.parent?.depth ?? -1
    case .child:
        newParentDepth = target.depth
    }
    let sourceSubtreeDepth = maxDepthOfSubtree(source) - source.depth
    let resultingMaxDepth = newParentDepth + 1 + sourceSubtreeDepth

    return resultingMaxDepth <= 2  // 0, 1, 2 = 3단계
}

func isDescendant(_ candidate: Task, of ancestor: Task) -> Bool {
    var current = candidate.parent
    while let node = current {
        if node.id == ancestor.id { return true }
        current = node.parent
    }
    return false
}

func maxDepthOfSubtree(_ task: Task) -> Int {
    if task.children.isEmpty { return task.depth }
    return task.children.map { maxDepthOfSubtree($0) }.max() ?? task.depth
}
```

### 5.2 드롭 후 처리

```swift
func performDrop(_ source: Task, onto target: Task, as mode: DropMode, in context: ModelContext) {
    // 1. 새 부모와 sortOrder 결정
    let newParent: Task?
    let newSortOrder: Int

    switch mode {
    case .siblingAbove:
        newParent = target.parent
        newSortOrder = target.sortOrder
        // target과 그 이후 형제들의 sortOrder를 +1
        shiftSortOrders(parent: newParent, from: target.sortOrder, by: 1)
    case .siblingBelow:
        newParent = target.parent
        newSortOrder = target.sortOrder + 1
        shiftSortOrders(parent: newParent, from: target.sortOrder + 1, by: 1)
    case .child:
        newParent = target
        newSortOrder = (target.children.map(\.sortOrder).max() ?? -1) + 1
    }

    // 2. source의 부모와 sortOrder 변경
    source.parent = newParent
    source.sortOrder = newSortOrder

    // 3. depth 재계산 (자기 자신 + 모든 자손)
    recalculateDepth(source)

    try? context.save()
}

func recalculateDepth(_ task: Task) {
    task.depth = (task.parent?.depth ?? -1) + 1
    for child in task.children {
        recalculateDepth(child)
    }
}
```

### 5.3 자정 롤오버 감지

앱이 메뉴바에서 열릴 때마다 (또는 일정 주기로) 다음을 수행:

```swift
func checkForCarryOverNeeded(context: ModelContext) {
    let today = Calendar.current.startOfDay(for: .now)

    // 오늘 이전 날짜에 할당된 미완료 테스크 조회
    let descriptor = FetchDescriptor<Task>(
        predicate: #Predicate {
            $0.assignedDate < today &&
            $0.status != .completed &&
            $0.parent == nil  // 메인 테스크만 (자식은 자동 따라감)
        }
    )

    guard let pendingTasks = try? context.fetch(descriptor) else { return }

    for task in pendingTasks {
        task.needsCarryOverDecision = true
    }

    try? context.save()
}
```

UI에서는 `needsCarryOverDecision == true`인 테스크가 하나라도 있으면 이월 결정 모드를 표시한다.

### 5.4 FOCUS 토글 (부모 동반 처리)

작업이 부모이면 자기 자신 + 모든 자손에 동일하게 `isFocused`를 적용한다. 자식 단독을 올린 경우엔 그 자식의 자손까지만 적용된다.

```swift
func toggleFocus(_ task: Task, in context: ModelContext) {
    let newValue = !task.isFocused
    setFocusRecursively(task, to: newValue, context: context)
    try? context.save()
}

private func setFocusRecursively(_ task: Task, to value: Bool, context: ModelContext) {
    task.isFocused = value
    if value {
        task.focusOrder = nextFocusOrder(context: context)
    }
    for child in task.children {
        setFocusRecursively(child, to: value, context: context)
    }
}

private func nextFocusOrder(context: ModelContext) -> Int {
    var descriptor = FetchDescriptor<Task>(
        predicate: #Predicate { $0.isFocused == true },
        sortBy: [SortDescriptor(\.focusOrder, order: .reverse)]
    )
    descriptor.fetchLimit = 1
    return ((try? context.fetch(descriptor).first?.focusOrder) ?? -1) + 1
}
```

완료 시 자동 해제:

```swift
func completeTask(_ task: Task, in context: ModelContext) {
    task.status = .completed
    task.completedAt = .now
    task.isFocused = false   // FOCUS 자동 해제
    try? context.save()
}
```

### 5.5 가장 빨리 끝나는 타이머 조회

메뉴바 텍스트 갱신용:

```swift
func nearestTimerEndsAt(context: ModelContext) -> Date? {
    let now = Date.now
    let descriptor = FetchDescriptor<Task>(
        predicate: #Predicate { $0.timerEndsAt != nil && $0.timerEndsAt! > now },
        sortBy: [SortDescriptor(\.timerEndsAt)]
    )
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first?.timerEndsAt
}
```

---

## 6. 프로젝트 셋업 가이드

### 6.1 Xcode 프로젝트 생성

1. Xcode 16+ 실행 → **Create New Project**
2. 상단 탭에서 **macOS** 선택
3. **App** 템플릿 선택 → Next
4. 다음 정보 입력:
   - Product Name: `Tempo`
   - Team: 사용자 Apple ID
   - Organization Identifier: `com.daegun.tempo` (사용자 도메인 형식)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **SwiftData** (체크)
   - Include Tests: 끔 (필요 시 나중에 추가)
5. Create

### 6.2 메뉴바 앱 설정

#### A. Info.plist에 LSUIElement 추가

프로젝트 파일 → 타겟 선택 → **Info** 탭 → **Custom macOS Application Target Properties**에 추가:

| Key | Type | Value |
|-----|------|-------|
| `Application is agent (UIElement)` | Boolean | `YES` |

이로 인해:
- Dock에 아이콘 표시 안 됨
- Cmd+Tab 앱 전환 목록에 안 뜸
- 메뉴바에만 존재하는 앱이 됨

#### B. TempoApp.swift 수정

기본 생성된 코드를 다음으로 교체:

```swift
import SwiftUI
import SwiftData

@main
struct TempoApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Task.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer 생성 실패: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .modelContainer(sharedModelContainer)
        } label: {
            MenuBarLabel()
                .modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}
```

**중요**: `.menuBarExtraStyle(.window)`를 반드시 설정. 기본값 `.menu`는 표준 macOS 메뉴 형태라 커스텀 SwiftUI 뷰를 그릴 수 없다.

#### C. 알림 권한 요청

앱 시작 시 알림 권한 요청 코드 추가:

```swift
import UserNotifications

// AppDelegate 또는 앱 초기화 시점에서
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
    // 처리
}
```

---

## 7. 구현 순서 (권장)

다음 순서대로 점진적으로 구현하고, 각 단계마다 빌드해서 동작 확인 후 진행한다.

### Step 1: 메뉴바 앱 골격
- Xcode 프로젝트 생성
- LSUIElement 설정
- `MenuBarExtra` + `.window` 스타일
- 임시 placeholder 뷰로 메뉴바에 점만 뜨게 만들기
- **완료 기준**: 빌드/실행 시 메뉴바 우측에 아이콘이 뜨고, 클릭 시 빈 창이 뜸. Dock에는 아이콘 없음

### Step 2: Task 모델 + SwiftData 셋업
- `Task.swift` 파일 생성, 위 명세대로 `@Model` 선언
- `TaskStatus` enum 정의
- `ModelContainer` 설정
- **완료 기준**: 컴파일 성공. `@Query`로 빈 배열을 가져오는 테스트 가능

### Step 3: 메인 드롭다운 뷰 (정적)
- 헤더 (앱 이름 + 오늘 날짜)
- 테스크 리스트 (재귀적으로 children 렌더링, depth에 따라 들여쓰기)
- 입력창 (하단 고정)
- **완료 기준**: 하드코딩한 더미 데이터를 화면에 표시 가능

### Step 4: 테스크 추가 기능
- 입력창에 텍스트 입력 후 Enter → 메인 테스크 추가
- 위 리스트에서 테스크 클릭 → 선택 상태로 전환
- 선택된 상태에서 입력 → 선택된 테스크의 하위로 추가
- depth 2 선택 시 입력창 비활성화
- ESC로 선택 해제
- **완료 기준**: 다양한 깊이의 테스크를 자유롭게 추가 가능

### Step 5: 테스크 완료/삭제
- 체크박스 클릭 시 `status` 토글
- 완료된 테스크는 취소선 + 흐린 색상
- 우클릭 메뉴 또는 swipe로 삭제 기능
- **완료 기준**: 완료/삭제 동작이 SwiftData에 영속화됨

### Step 6: 타이머 기능
- 시작 버튼 클릭 시 `timerStartedAt`, `timerEndsAt` 설정
- 매 초 갱신되는 카운트다운 표시
- 일시정지 기능
- 메뉴바 텍스트에 가장 빠른 타이머의 남은 시간 표시
- **완료 기준**: 동시에 여러 타이머가 돌아가고, 메뉴바에 가장 빠른 시간이 표시됨

### Step 7: 시스템 알림
- `UserNotifications` 권한 요청
- 타이머 종료 시점에 알림 스케줄링
- 알림 액션 (`+5분`, `+15분`, `완료`) 등록 및 핸들링
- **완료 기준**: 타이머 끝나면 알림 뜨고, 액션 버튼이 동작함

### Step 8: 드래그앤드롭
- `.draggable()`과 `.dropDestination()` 적용
- 3가지 드롭 영역 판정 (위/가운데/아래)
- 시각적 피드백 (가로 라인, 하이라이트)
- 검증 로직 (자손 드롭 방지, 3단계 초과 방지)
- 드롭 후 depth 재계산
- **완료 기준**: 자유로운 트리 재구성이 가능하며, 잘못된 드롭은 차단됨

### Step 9: 자정 롤오버 + 이월 결정 UI
- 메뉴바 열릴 때마다 어제 미완료 테스크 체크
- `needsCarryOverDecision` 플래그 설정
- 이월 결정 모드 뷰 구현
- "오늘로 가져오기" / "완료 처리" 동작
- 일괄 처리 버튼
- **완료 기준**: 시스템 시간을 다음날로 바꾸고 메뉴바를 열면 이월 결정 UI가 뜸

### Step 10: FOCUS / QUEUE / COMPLETED 3영역
- `isFocused`, `focusOrder` 필드 추가 + SwiftData 마이그레이션
- 드롭다운을 세 영역(FOCUS·QUEUE·COMPLETED)으로 분리한 뷰 구조
- `Cmd+F` 단축키 + 부모 동반 토글 로직 (5.4)
- QUEUE의 음영 표시 (`circle.dotted` 또는 회색 처리)
- FOCUS 자식 단독 진입 시 출처 부모 경로 라벨
- COMPLETED 접힘/펼침 토글 + 카운터
- 작업 완료 시 페이드아웃 + COMPLETED로 이동 + `isFocused` 자동 해제
- FOCUS 내부 드래그앤드롭 정렬
- **완료 기준**: 부모 작업을 FOCUS에 올리면 자손까지 따라오고, QUEUE에선 그 트리가 음영으로 보이며, 체크 시 즉시 COMPLETED로 이동함

### Step 11: 과거 모드 (날짜 네비게이션)
- 헤더에 `◀ / ▶` 화살표 + `[오늘로]` 버튼
- `Cmd+[`, `Cmd+]`, `Cmd+T` 단축키
- 과거 날짜 진입 시 FOCUS·QUEUE 영역 숨김, COMPLETED만 펼친 상태로 표시
- 과거 모드 입력창 비활성화
- 미래 날짜 이동 차단
- **완료 기준**: 어제로 이동하면 어제 완료한 일들만 보이고, 오늘로 복귀하면 일반 3영역으로 돌아옴

### Step 12: 폴리싱
- 애니메이션 추가 (테스크 추가/삭제, FOCUS 토글, 모드 전환)
- 키보드 단축키 (Cmd+N: 새 메인 테스크 등)
- 자동시작 (로그인 시 자동 실행) 옵션
- 설정 화면 (필요 시)
- 빈 상태 (테스크가 하나도 없을 때) UI

---

## 8. 작업 시 주의사항

### 8.1 깊이 변경 시 자손 처리
- `parent`를 변경할 때마다 자기 자신과 모든 자손의 `depth`를 재계산해야 한다
- 이를 빠뜨리면 3단계 제한 검증이 깨진다

### 8.2 타이머 캐시 일관성
- `timerStartedAt`, `plannedDuration`, `timerEndsAt` 세 필드 간 일관성을 유지해야 한다
- 시간 수정 시 세 필드 모두 적절히 갱신할 것

### 8.3 SwiftData 트랜잭션
- 여러 필드를 한꺼번에 변경하는 경우 (드롭 후 부모/sortOrder/depth 갱신 등) 마지막에 한 번만 `try? context.save()` 호출
- SwiftData는 자동으로 변경을 추적하지만, 명시적 저장이 안전함

### 8.4 시간대 처리
- 모든 날짜 비교는 `Calendar.current.startOfDay(for:)`로 정규화
- 사용자가 시간대를 바꾸는 경우는 1차 버전에서 고려하지 않음 (현재 시간대 기준으로만 동작)

### 8.5 디자인 강제 사항 (재차 강조)
- **이모지 사용 금지**
- **그라디언트 배경 사용 금지**
- 모든 아이콘은 SF Symbols
- 모든 색상은 시스템 시맨틱 컬러 (`Color.primary`, `Color.secondary`, `Color.accentColor` 등)
- Things 3, Linear, Fantastical 같은 정통 macOS 네이티브 앱의 미감 유지

### 8.6 macOS 권한
- 알림 권한 (필수)
- 자동시작은 `ServiceManagement` 프레임워크 사용 (선택, Step 12에서)
- 첫 실행 시 사용자에게 권한 요청 흐름이 자연스러워야 함

### 8.7 FOCUS 자동 동반 일관성
- 부모를 FOCUS에 올리거나 내릴 때 모든 자손도 함께 따라가야 한다 (5.4 참고)
- 자식만 올린 상태에서 부모를 다시 올리면, 그 자식은 이미 `isFocused=true`이므로 멱등하게 동작. 자손 전체에 `setFocusRecursively`를 호출해도 안전함.
- 트리 재구성(드래그앤드롭으로 부모 변경) 시 `isFocused`는 사용자 의도와 어긋날 수 있다. 1차 버전 규칙: **부모를 변경하면 자기 자신의 `isFocused`는 유지하되, 새 부모와 동기화는 강제하지 않는다.** (즉 사용자가 새 부모를 명시로 FOCUS에 올려야 함)
- 작업 완료 시엔 항상 `isFocused=false`로 설정한다 (자손이라도). 자손 완료가 부모 FOCUS 상태에 영향을 주지는 않는다.

### 8.8 과거 모드 입력 보호
- 과거 모드 진입 시 입력창 disable 처리
- 단축키 `Cmd+F`도 과거 모드에선 무시 (FOCUS 자체가 숨겨져 있으므로)

---

## 9. 향후 확장 가능성 (1차 버전엔 미포함)

다음은 이 프로젝트가 성숙해지면 추가할 수 있는 기능들이다. **1차 버전에서는 구현하지 않으며**, 데이터 구조도 이를 위해 미리 변경하지 않는다 (필요 시 나중에 마이그레이션).

- 회고 기능 (일자별 스냅샷, 통계)
- iCloud 동기화 (여러 Mac 간)
- 키보드 단축키 커스터마이징
- 테마 (라이트/다크 외)
- 카테고리/태그
- 반복 테스크
- 캘린더 통합

---

## 10. 결정 이력

이 프로젝트의 주요 의사결정 이력을 기록한다.

| 결정 사항 | 결정 |
|-----------|------|
| 앱 형태 | 메뉴바 앱 (윈도우 앱이 아닌 이유: 항상 시야에 두기 위해) |
| 이름 | Tempo |
| 기술 스택 | Swift + SwiftUI 네이티브 (Electron/Tauri 아님) |
| 영속화 | SwiftData (Core Data, SQLite 직접이 아님) |
| 계층 깊이 | 3단계 제한 (무한 중첩 거부) |
| 메뉴바 타이머 표시 | 가장 빠른 종료 시간만 (개수 표시 없음) |
| 다중 타이머 | 동시 실행 허용 |
| 완료된 테스크 | 당일에는 표시, 자정 후 사라짐 |
| 이월 결정 시점 | 다음날 첫 메뉴바 오픈 시 (자정 즉시 아님) |
| 이월 결정 UI | 모든 결정 완료 전엔 일반 화면 진입 불가 |
| 하위 테스크 부모 지정 | 위쪽 테스크 선택 후 입력 시 자동으로 그 자식이 됨 |
| 드래그 범위 | 형제 순서 + 부모 변경 모두 가능 |
| 회고 기능 | 1차 버전 미포함. 단, COMPLETED 섹션과 과거 모드는 기본 제공 |
| 디자인 톤 | 이모지/그라디언트 금지, SF Symbols + 시스템 컬러 |
| 드롭다운 영역 구조 | FOCUS / QUEUE / COMPLETED 3영역으로 분리 |
| FOCUS와 타이머 | 완전 독립. 자동 연동 없음 |
| FOCUS 부모 동반 | 부모를 올리면 자손 전체가 함께 진입·이탈 |
| FOCUS-QUEUE 중복 표시 | FOCUS에 올라간 작업은 QUEUE에서 음영으로 남음 (트리 보존) |
| 완료된 작업 처리 | QUEUE/FOCUS에서 즉시 제거, COMPLETED로 이동, 자정 후 오늘 모드에선 사라짐 |
| 완료 데이터 보존 | 영구 보존. 과거 모드에서 조회 |
| 과거 모드 | 오늘 아닌 날짜 진입 시 COMPLETED만 펼친 상태로 표시 |
| COMPLETED 정렬 | 완료 시각 정순 (오래된 게 위) |

---

문서 끝.
