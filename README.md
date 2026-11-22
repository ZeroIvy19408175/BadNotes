# BadNotes

굿노트 너무 비싸고, 아이패드 너무 구리고, 나는 거지다.
그래서 만들었다.

앱도 거지같다.

---

- iPad용 PDF 필기 앱 (SwiftUI + PDFKit + PencilKit), iPadOS 17 이상
- 원본 PDF는 앱 폴더에 한 번 복사만 하고 절대 다시 쓰지 않음
- 필기는 `<파일이름>.notes/pageN.drawing`에 페이지별로 따로 저장 (atomic 저장, 자동)
- 오류 나면 빨간 배너 + 로그 창
- 스크롤하면 상단 바 숨김, 제목 누르면 페이지 이동

## 알려진 문제
- 마지막 페이지 끝까지 스크롤하면 상단 바가 숨었다 나왔다 하면서 버벅이다 멈춤
- 필기가 PDF 안에 안 박혀서, 다른 앱으로 보내면 필기 안 보임

## 빌드
Xcode로 `BadNotes.xcodeproj` 열고 Signing에서 본인 팀 골라서 실행.
