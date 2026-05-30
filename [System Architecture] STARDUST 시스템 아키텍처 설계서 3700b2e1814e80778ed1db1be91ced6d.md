# [System Architecture] STARDUST 시스템 아키텍처 설계서

공모전 심사위원단(개발 및 기획 전문가)에게 우리 서비스의 기술적 완성도(30점)와 데이터 처리 구조를 시각적·논리적으로 증명하기 위한 **아키텍처 다이어그램 기반 시스템 재설계서**입니다.

요청하신 4단계 파이프라인(**클라이언트 ➡️ Web Server ➡️ Back-end ➡️ DataBase**)의 데이터 흐름에 맞춰, 시스템 구성과 데이터 포맷을 정밀하게 설계했습니다.

```
[클라이언트]  ◀==== (JSON 응답) ==== [Web Server]  ◀==== [Back-end]  ◀==== [DataBase]
(SwiftUI 앱)       (HTTPS 통신)      (Nginx / API)     (Node.js Express)   (PostgreSQL + PostGIS)
     │                                    ▲                 │                   ▲
     └=========== (JSON 요청) ===========┘                 └=== (Query/추출) ==┘
```

## 1. 구조별 상세 설계 (Layer Architecture)

### 📱 1.1 클라이언트 (Client / 브라우저·앱)

- **역할:** 유저 터치 제어 및 하드웨어 센서(GPS, 카메라, 자이로스코프) 데이터 캡처.
- **작동:** 한국관광공사 OpenAPI 기반 명소에 진입하면 카메라 뷰를 활성화합니다. 하늘 촬영 시 이미지 바이너리를 `Base64` 문자열로 인코딩하고, 현재 기기의 정밀 위경도 좌표(GPS)와 함께 JSON 패킷으로 묶어 Web Server로 전송합니다.

### 🌐 1.2 웹 서버 (Web Server / HTTP 통신 인프라)

- **기술 스택:** **Nginx** (Reverse Proxy)
- **역할:** 클라이언트와 백엔드 사이의 게이트웨이 및 암호화 통신 통제.
- **보안 및 처리:**
    - **TLS 1.3 암호화:** 유저의 실시간 동선 및 위치 데이터 가로채기(Sniffing)를 방지하기 위해 모든 요청을 HTTPS 프로토콜로 강제 전환합니다.
    - **Rate Limiting (디도스 방지):** 악의적인 매크로나 GPS 변조 봇이 무한대로 API를 호출해 서버를 마비시키는 것을 방지하기 위해 IP당 분당 요청 횟수를 제한합니다.

### ⚙️ 1.3 백엔드 (Back-end / 비즈니스 로직 연산)

- **기술 스택:** **Node.js (Express)**
- **역할:** JWT 인증 검증, 이미지 색상 추출 알고리즘 실행, 위치 난독화 보안 처리.
- **핵심 비즈니스 로직 파이프라인:**
    1. **JWT 검증:** 요청 헤더의 `Authorization` 토큰을 해석해 올바른 유저인지 식별합니다.
    2. **공간 난독화 (Safe Zone 적용):** 유저의 보호 구역(집) 좌표 내부일 경우, 좌표 오차를 무작위로 발생시켜 사생활을 보호합니다.
    3. **색상 값(Hex) 추출:** 업로드된 하늘 이미지의 픽셀 데이터를 분석하여 대표 파스텔톤 컬러 코드를 연산해 냅니다.

### 🗄️ 1.4 데이터베이스 (DataBase / 영속성 데이터 저장소)

- **기술 스택:** **PostgreSQL + PostGIS 확장 모듈** (Supabase 인프라 활용)
- **역할:** 유저 정보 저장, 실시간 위치 공간 데이터 연산 및 인덱싱.
- **특장점:** 한국관광공사 API에서 가져온 대용량 관광지 좌표(`geometry` 타입)와 유저가 생성한 별의 좌표를 PostGIS의 공간 인덱스(R-Tree)를 통해 관리합니다. 덕분에 "내 주변 1km 이내 관광지 검색" 쿼리를 단 몇 밀리초($\text{ms}$) 만에 처리할 수 있어 심사 항목 중 **기능적 우수성**을 확보합니다.

## 2. 아키텍처 기반 End-to-End 데이터 흐름 (Data Flow 명세)

유저가 관광지에서 하늘을 찍어 '자신의 자취(별)를 밤하늘에 등록하는 핵심 순간'의 데이터 트랜잭션 흐름입니다.

### 🔄 [Step 1] 클라이언트 ➡️ 웹 서버 (요청 / Request)

- **Protocol:** HTTPS (POST)
- **Endpoint:** `[https://api.stardust.app/api/v1/stars](https://api.stardust.app/api/v1/stars)`
- **Headers:**HTTP
    
    ```
    Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
    Content-Type: application/json
    ```
    
- `**JSON Payload:** ```json { "tour_id": "301245", "latitude": 37.7725, "longitude": 128.9478, "image_base64": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ..." }`

### 🔄 [Step 2] 웹 서버 ➡️ 백엔드 (라우팅 및 연산)

- Nginx가 SSL 복호화 후 Node.js 내부 포트로 안전하게 포워딩합니다.
- 백엔드 엔진은 `image_base64` 데이터를 디코딩하여 이미지 분석 모듈을 통과시킨 뒤, 하늘의 지배적인 색상(예: 노을빛 연분홍)인 `#FFB6C1`을 도출해 냅니다.

### 🔄 [Step 3] 백엔드 ➡️ 데이터베이스 (쿼리 / SQL Query)

- 정제된 데이터와 위치 객체를 PostgreSQL의 PostGIS 규격에 맞추어 `INSERT` 문으로 전달합니다.
- **실행 쿼리 예시:**SQL
    
    ```
    INSERT INTO stars (user_id, tour_id, location, sky_color_hex, created_at)
    VALUES (
      'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
      '301245',
      ST_SetSRID(ST_MakePoint(128.9478, 37.7725), 4326),
      '#FFB6C1',
      NOW()
    );
    ```
    

`### 🔄 [Step 4] 웹 서버 ➡️ 클라이언트 (응답 / Response)
*   DB 저장이 완료되면 백엔드와 웹 서버를 거쳐 최종 가공된 JSON 결과가 클라이언트(앱)에 도달합니다.
*   **HTTP Status:** `21 Created`
*   **JSON Response:**
    ```json
    {
      "status": "success",
      "message": "당신의 자취가 밤하늘의 별로 기록되었습니다.",
      "data": {
        "star_id": 1205,
        "sky_color_hex": "#FFB6C1",
        "created_at": "2026-05-30T20:40:00Z"
      }
    }`

- **클라이언트 최종 연출:** 앱은 이 응답을 받는 즉시 화면상의 3D 가상 공간에 `#FFB6C1` 색상으로 빛나는 별 오브젝트를 드로잉하고, 이전 별과 선으로 연결하여 실시간 은하수 인터랙션을 완성합니다.

공모전 심사 시 이처럼 인프라 구조와 4단계 데이터 흐름을 명확한 기술 용어와 JSON 예시로 증명하면, 아이디어의 참신함뿐만 아니라 "즉시 상용화 및 출시가 가능한 고도화된 서비스(20점)"라는 강력한 인상을 심어줄 수 있습니다. 기획서 파일에 그대로 통합하여 제출하세요!