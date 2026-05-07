# Tempo

macOS 메뉴바에 상주하는 TODO 앱. 클릭 한 번으로 오늘 할 일을 확인하고, 타이머로 작업 시간을 관리한다.

## 목차

- [설치 방법](#설치-방법)
  - [요구 사항](#요구-사항)
  - [빌드 및 설치](#빌드-및-설치)
  - [업데이트](#업데이트)
- [업데이트 내용](#업데이트-내용)
  - [드래그앤드롭 UX 안정화](#드래그앤드롭-ux-안정화)
  - [진행 중 상태 표시 및 정렬](#진행-중-상태-표시-및-정렬)
  - [입력 UX 개선](#입력-ux-개선)
  - [항목 수정·선택·삭제](#항목-수정선택삭제)
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

### 드래그앤드롭 UX 안정화
- 박스 본체에 드롭하면 자식, 위/아래 가장자리에 드롭하면 형제로 명확히 구분
- 가장자리에서도 X 우측 60%로 끌면 자식으로 승격
- DragGesture를 제목 영역에만 부착해 체크박스/타이머 버튼 우발적 토글 제거
- 드래그 중 행이 커서를 따라 이동(offset/그림자/zIndex)
- drop line이 대상 항목의 depth에 맞춰 들여쓰기, child 모드는 한 단계 더 들여쓴 ghost line 표시
- 트리는 같은 `assignedDate`를 공유하도록 `performDrop`에서 동기화 → 드롭 후 항목이 화면에서 사라지는 버그 제거

### 진행 중 상태 표시 및 정렬
- 행 가운데에 "진행중" 워터마크(파랑 22pt heavy rounded, opacity 0.22) 표시
- 우클릭 메뉴에 "진행 시작/중지" 추가 — 타이머 없는 항목도 수동 토글 가능
- 진행 중 항목을 포함한 root 트리는 같은 레벨에서 자동으로 위로 정렬, 트리 내부 순서는 유지

### 입력 UX 개선
- "하위" 라벨 클릭 또는 Tab 키 → 메인 모드로 전환
- 새 항목 추가 시 화면 가운데로 부드럽게 자동 스크롤 (0.35s easeInOut)
- "수정" 라벨 표기 제거(라벨은 항상 메인/하위)

### 항목 수정·선택·삭제
- 더블 클릭 → 입력창에 해당 항목 내용이 채워져 인라인 수정
- 더블 클릭 시 선택 표시도 해당 항목으로 이동
- 행 선택 후 Backspace로 삭제 (NSEvent local monitor, 입력창 포커스 시 텍스트 편집 우선)

## 사용법

| 동작 | 방법 |
|------|------|
| 드롭다운 열기 | 메뉴바 체크마크 아이콘 좌클릭 |
| About / 종료 | 메뉴바 아이콘 우클릭 |
| 메인 테스크 추가 | 하단 입력창에 입력 후 Enter |
| 하위 테스크 추가 | 테스크 클릭(선택) 후 입력 |
| 선택 해제 | ESC 또는 빈 영역 클릭 |
| 테스크 완료 | 좌측 체크박스 클릭 |
| 테스크 수정 | 우클릭 > 수정 |
| 테스크 삭제 | 우클릭 > 삭제 |
| 순서/계층 변경 | 드래그앤드롭 |
| 날짜 이동 | 헤더의 좌/우 화살표 |
| 날짜 선택 | 헤더의 날짜 텍스트 클릭 > 캘린더 |
| 타이머 시작 | 테스크 우측 재생 버튼 |
| 시간 설정 | 테스크 추가 시 "분" 필드에 입력 |

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
