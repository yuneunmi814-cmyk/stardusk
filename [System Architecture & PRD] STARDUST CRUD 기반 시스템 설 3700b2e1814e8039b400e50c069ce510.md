# [System Architecture & PRD] STARDUST CRUD 기반 시스템 설계서

제공해주신 공모전 공고문의 자격 요건과 심사 기준, 그리고 요청하신 **CRUD(Create, Read, Update, Delete) 표준 개념**을 완벽하게 적용하여 아키텍처 흐름 기반 기획안을 최종 수정했습니다.

심사위원들이 데이터베이스 트랜잭션의 무결성과 데이터 처리 과정을 한눈에 파악할 수 있도록, **클라이언트 ➡️ Web Server ➡️ Back-end ➡️ DataBase**로 이어지는 4단계 정방향/역방향 흐름 속에 CRUD 매핑과 HTTP 메서드를 명확하게 명시했습니다.

```
[정방향: 요청 흐름 (Request Data Flow)]
클라이언트 (SwiftUI) ── 요청 (HTTP 메서드) ──▶ Web Server (Nginx) ──▶ Back-end (Node.js) ──▶ DataBase (CRUD 수행)

[역방향: 응답 흐름 (Response Data Flow)]
클라이언트 (3D 인터랙션) ◀── 응답 (JSON) ── Web Server (HTTPS) ◀── Back-end (결과 정제) ◀── DataBase (트랜잭션 완료)
```

## 1. 4단계 아키텍처별 CRUD 연산 및 데이터 흐름

### ① 클라이언트 (Client / SwiftUI 모바일 앱)

- **Create/Post (생성):** 유저가 지정된 관광지에서 하늘을 촬영하는 즉시 기기의 정밀 위경도(GPS) 좌표와 이미지(`Base64`)를 담아 `POST` 요청을 발송합니다.
- **Read/Get (조회):** 내 주변의 관광공사 OpenAPI 정화 스팟을 확인하거나, 집으로 돌아와 내가 쌓아온 은하수(별자리) 데이터를 화면에 렌더링하기 위해 `GET` 요청을 발송합니다.
- **Update/Patch (수정):** 유저가 자신이 생성한 별자리의 이름이나 한 줄 소회를 변경할 때 `PATCH` 요청을 보냅니다.
- **Delete/Delete (삭제):** 특정 별이나 전체 여정 흔적을 지우고 싶을 때 `DELETE` 요청을 보냅니다.

### ② 웹 서버 (Web Server / Nginx)

- **인증 및 라우팅:** 클라이언트가 전송한 HTTP 메서드(`GET`, `POST`, `PATCH`, `DELETE`)와 REST URL을 식별하여 백엔드의 해당 CRUD 컨트롤러로 요청을 안전하게 포워딩합니다.
- **응답 반환:** 백엔드가 CRUD 연산 후 리턴한 메시지와 HTTP 상태 코드(`200 OK`, `201 Created`, `204 No Content`)를 클라이언트에게 전달합니다.

### ③ 백엔드 (Back-end / Node.js Express)

- **비즈니스 로직 및 객체 매핑:** * `POST` 요청 시 이미지 색상 추출 및 공간 난독화(Safe Zone) 보안 가공을 거쳐 DB에 삽입할 데이터를 빌드합니다.
    - `GET` 요청 시 데이터베이스에서 위치 기반 쿼리 결과를 받아 클라이언트가 표현하기 좋은 깔끔한 JSON 형태로 정제합니다.

### ④ 데이터베이스 (DataBase / PostgreSQL + PostGIS)

- **CRUD 엔진:** 백엔드로부터 요청받은 SQL 문을 실행하여 실제 하드웨어 디스크에 영속성 데이터를 기록, 읽기, 수정, 삭제하는 심장부 역할을 합니다. (공간 데이터 연산 인덱싱 처리 포함)

## 2. API 명세서 연동형 CRUD 세부 명세

### ➕ 2.1 Create (생성) ── [POST]

- **Endpoint:** `POST /api/v1/stars`
- **설명:** 유저가 하늘을 촬영하여 특정 관광지 좌표에 자신만의 자취(별)를 등록하는 핵심 생성 연산입니다.
- **Data Flow:**
    - `클라이언트` ── `POST (JSON)` ──→ `Web Server` ──→ `Back-end (색상 추출/난독화)` ──→ `DataBase (INSERT)`
- **요청 Body (JSON):**JSON
    
    ```
    {
      "tour_id": "301245",
      "latitude": 37.7725,
      "longitude": 128.9478,
      "image_base64": "data:image/jpeg;base64,/9j/4AAQ..."
    }
    ```
    
- **응답 (201 Created):**JSON
    
    ```
    {
      "status": "success",
      "message": "새로운 별(자취)이 생성되었습니다.",
      "data": { "star_id": 9845, "sky_color_hex": "#A1C4FD" }
    }
    ```
    

### 🔍 2.2 Read (조회) ── [GET]

- **Endpoint:** `GET /api/v1/stars/my-galaxy`
- **설명:** 유저가 그동안 여행하며 쌓아온 모든 별들과 이를 연결한 은하수(동선) 데이터를 조회하여 3D 자이로스코프 화면에 구현하기 위한 연산입니다.
- **Data Flow:**
    - `클라이언트` ── `GET` ──→ `Web Server` ──→ `Back-end` ──→ `DataBase (SELECT)`
- **응답 (200 OK):**JSON
    
    ```
    {
      "status": "success",
      "data": {
        "total_stars_count": 2,
        "stars_trail": [
          { "star_id": 9841, "latitude": 37.7951, "longitude": 128.8964 },
          { "star_id": 9845, "latitude": 37.7725, "longitude": 128.9478 }
        ]
      }
    }
    ```
    

### ✏️ 2.3 Update (수정) ── [PATCH]

- **Endpoint:** `PATCH /api/v1/stars/constellations/{id}`
- **설명:** 유저가 생성된 자신만의 별자리(동선 그룹)의 이름이나 감성 타이틀을 수정할 때 사용하는 연산입니다. (전체 교체가 아니므로 표준에 따라 `PUT` 대신 `PATCH`를 적용)
- **Data Flow:**
    - `클라이언트` ── `PATCH (JSON)` ──→ `Web Server` ──→ `Back-end` ──→ `DataBase (UPDATE)`
- **요청 Body (JSON):**JSON
    
    ```
    {
      "constellation_name": "바람이 머물던 안목해변"
    }
    ```
    
- **응답 (200 OK):**JSON
    
    ```
    {
      "status": "success",
      "message": "별자리 정보가 성공적으로 수정되었습니다."
    }
    ```
    

### ❌ 2.4 Delete (삭제) ── [DELETE]

- **Endpoint:** `DELETE /api/v1/stars/{id}`
- **설명:** 잘못 등록했거나 지우고 싶은 내 별의 자취를 영구히 삭제하는 연산입니다. 개인정보법 및 위치정보법에 의거하여 파기 요청 시 DB에서 즉시 완전 삭제 처리됩니다.
- **Data Flow:**
    - `클라이언트` ── `DELETE` ──→ `Web Server` ──→ `Back-end` ──→ `DataBase (DELETE)`
- **응답 (204 No Content):** * *특이사항:* 삭제 성공 시 REST 표준 규격에 따라 별도의 리턴 바디 없이 HTTP Status Code `204`만 깔끔하게 반환합니다.

## 3. 공모전 심사위원 대상 기술 소구 포인트 (Tip)

본 기획안은 HTTP 메서드와 DB의 CRUD 사이클을 1:1로 엄격하게 일치시켰습니다. 특히 데이터 수정 시 자원을 전체 교체하는 `PUT` 대신 부분 변경인 `PATCH`를 사용하고, 삭제 성공 시 `204 No Content` 상태 코드를 반환하는 등 **글로벌 RESTful API 아키텍처 표준을 완벽히 준수**하고 있음을 증명합니다.

이대로 공모전 기술 서류(PRD) 섹션에 제출하시면 '개발 즉시 구현 및 상용화가 가능한 고도화된 아키텍처 디자인'으로 인정받아 기술 완성도 부문에서 최고점을 확보하는 데 결정적인 역할을 할 것입니다!