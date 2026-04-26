# Tempo

macOS 메뉴바에 상주하는 TODO 앱. 클릭 한 번으로 오늘 할 일을 확인하고, 타이머로 작업 시간을 관리한다.

## 주요 기능

### 테스크 관리
- 3단계 계층 구조 (메인 > 하위 1 > 하위 2)
- 테스크 선택 후 입력하면 하위 테스크로 추가
- 드래그앤드롭으로 순서 변경 및 부모 이동
- 우클릭 > 수정으로 기존 테스크 편집
- 완료 시 Glass 사운드 재생

### 날짜 네비게이션
- 좌/우 화살표로 이전/다음 날짜 이동
- 날짜 클릭 시 커스텀 캘린더 팝오버
- 캘린더에 날짜별 테스크 수 표시
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
- 며칠째 진행 중인지 표시

## 기술 스택

| 항목 | 선택 |
|------|------|
| 플랫폼 | macOS 14.0+ |
| 언어 | Swift 5.9+ |
| UI | SwiftUI (MenuBarExtra) |
| 영속화 | SwiftData |
| 알림 | UserNotifications |
| IDE | Xcode 16+ |

## 프로젝트 구조

```
Tempo/
├── TempoApp.swift              # 앱 진입점, MenuBarExtra 설정
├── Models/
│   └── TodoTask.swift           # SwiftData 모델, TaskStatus enum
├── Services/
│   ├── TaskService.swift        # 생성/완료/삭제/타이머/이월/드롭 로직
│   ├── TimerManager.swift       # 메뉴바 타이머 갱신
│   ├── NotificationManager.swift # 시스템 알림 및 액션 핸들링
│   └── DragState.swift          # 드래그앤드롭 상태 관리
├── Views/
│   ├── MenuContentView.swift    # 메인 드롭다운 뷰
│   ├── MenuBarLabel.swift       # 메뉴바 아이콘 + 타이머 텍스트
│   ├── HeaderView.swift         # 헤더 (앱 이름 + 날짜 네비게이션)
│   ├── TaskRowView.swift        # 테스크 행 (체크박스, 타이머, 드래그)
│   ├── TaskInputView.swift      # 하단 입력창 (생성/수정)
│   ├── CarryOverView.swift      # 이월 결정 UI
│   └── CalendarPickerView.swift # 커스텀 캘린더 팝오버
```

## 빌드 및 실행

```bash
# xcodegen 설치 (최초 1회)
brew install xcodegen

# 프로젝트 생성
xcodegen generate

# Xcode에서 열기
open Tempo.xcodeproj
```

Xcode에서 Run (Cmd+R) 실행. Dock에는 표시되지 않고 메뉴바에만 체크마크 아이콘이 나타난다.

## 디자인 원칙

- SF Symbols 사용 (이모지 금지)
- 시스템 시맨틱 컬러 (다크/라이트 자동 대응)
- 시스템 폰트 (SF Pro)
- 그라디언트 배경 금지
- Things 3, Linear, Fantastical 같은 네이티브 macOS 앱 미감 추구
