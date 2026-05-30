# [API Specification] 프로젝트 STARDUST (별의 자취)

제공해주신 공모전 요구사항과 기술 스택(SwiftUI + Supabase)을 바탕으로, **HTTP / JSON / REST API 표준**을 철저히 준수한 **[STARDUST] 서비스의 백엔드 API 명세서**입니다.

팀 내 프론트엔드(iOS 개발자)와 백엔드 개발자가 즉시 통신 연동 계약(API Contract)을 맺고 탑재할 수 있도록 실제 상용화 수준의 JSON 포맷으로 작성했습니다.

## 1. 공통 보안 및 인증 방식 (Authentication)

- **인증 표준:** **JWT (JSON Web Token)**
- **인증 방식:** HTTP 요청 헤더(Header)의 `Authorization` 필드에 `Bearer {Access_Token}`을 첨부하여 전송합니다.
- **보안 규칙:** 회원가입/로그인 엔드포인트를 제외한 모든 API는 유효한 JWT 토큰이 헤더에 누적되어야만 접근이 가능합니다. (토큰 유효기간: 1시간)

## 2. API 명세서 개요 (Summary)

| **기능 분류** | **Endpoint URL** | **HTTP 메서드** | **설명** |
| --- | --- | --- | --- |
| **인증** | `/api/v1/auth/login` | **POST** | 소셜 로그인 및 JWT 발급 |
| **관광지** | `/api/v1/tour/spots` | **GET** | 내 주변 한국관광공사 API 기반 정화 스팟 조회 |
| **정화 및 별 생성** | `/api/v1/stars` | **POST** | 하늘 촬영 후 위치에 내 별(자취) 등록 |
| **은하수 조회** | `/api/v1/stars/my-galaxy` | **GET** | 내가 쌓아온 별자리(동선) 데이터 조회 |

## 3. 엔드포인트별 상세 명세 (Endpoints)

### 🔑 3.1 소셜 로그인 및 인증 토큰 발급

- **Endpoint:** `/api/v1/auth/login`
- **HTTP Method:** `POST`
- **Description:** Google/Apple 인증 후 전달받은 자격증명으로 서비스 회원가입 또는 로그인을 처리하고 내부 JWT 토큰을 발급합니다.

### Request Body

JSON

```
{
  "provider": "google",
  "identity_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6...",
  "nickname": "푸른요정"
}
```

### Response (200 OK)

JSON

```
{
  "status": "success",
  "message": "인증에 성공했습니다.",
  "data": {
    "user_id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
    "nickname": "푸른요정",
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expires_in": 3600
  }
}
```

### 🗺️ 3.2 내 주변 관광공사 정화 스팟(PoI) 조회

- **Endpoint:** `/api/v1/tour/spots`
- **HTTP Method:** `GET`
- **Authentication:** `Bearer {Access_Token}` 필요
- **Description:** 유저의 현재 위경도를 기반으로 한국관광공사 OpenAPI를 호출·필터링하여 반경 내의 정화 가능 관광지 목록을 반환합니다. (보안 처리를 위해 유저의 실제 위치는 파라미터 전송 시 TLS 암호화 구간을 거칩니다.)

### Query Parameters

- `latitude`: 37.7914 (유저 현재 위도)
- `longitude`: 128.9194 (유저 현재 경도)
- `radius`: 1000 (반경 설정, 미터 단위)

### Response (200 OK)

JSON

```
{
  "status": "success",
  "data": [
    {
      "tour_id": "301245",
      "spot_name": "강릉 안목해변 커피거리",
      "region": "강원도 강릉시",
      "latitude": 37.7725,
      "longitude": 128.9478,
      "distance_meters": 450
    },
    {
      "tour_id": "128954",
      "spot_name": "경포대 도립공원",
      "region": "강원도 강릉시",
      "latitude": 37.7951,
      "longitude": 128.8964,
      "distance_meters": 820
    }
  ]
}
```

### 📸 3.3 하늘 촬영 및 별(자취) 생성

- **Endpoint:** `/api/v1/stars`
- **HTTP Method:** `POST`
- **Authentication:** `Bearer {Access_Token}` 필요
- **Description:** 유저가 하늘을 정화 촬영했을 때 호출됩니다. 위치 정보법에 의거하여 거주지 보호를 위한 위치 난독화 보안 처리 알고리즘(Safe Zone 보호)이 백엔드 내부에서 작동한 뒤 DB에 저장됩니다.

### Request Body

JSON

```
{
  "tour_id": "301245",
  "latitude": 37.7725,
  "longitude": 128.9478,
  "sky_color_hex": "#A1C4FD",
  "image_base64": "iVBORw0KGgoAAAANSUhEUgAA..."
}
```

### Response (201 Created)

JSON

```
{
  "status": "success",
  "message": "당신의 자취가 밤하늘의 별로 기록되었습니다.",
  "data": {
    "star_id": 9845,
    "user_id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
    "sky_color_hex": "#A1C4FD",
    "image_url": "https://storage.stardust.app/sky/2026/05/star_9845.jpg",
    "created_at": "2026-05-30T20:35:00Z"
  }
}
```

### 🌌 3.4 나만의 은하수(별자리 동선) 조회

- **Endpoint:** `/api/v1/stars/my-galaxy`
- **HTTP Method:** `GET`
- **Authentication:** `Bearer {Access_Token}` 필요
- **Description:** 집(일상)으로 돌아온 유저가 3D 자이로스코프 감상 모드를 켰을 때 호출되는 API입니다. 그동안 쌓아온 별의 시간 순서적 동선 연결값(LineString 구조 표현 데이터)을 반환합니다.

### Response (200 OK)

JSON

```
{
  "status": "success",
  "data": {
    "total_stars_count": 34,
    "constellation_name": "강릉을 수놓은 영혼의 자리",
    "stars_trail": [
      {
        "star_id": 9841,
        "sky_color_hex": "#FFF6D6",
        "latitude": 37.7951,
        "longitude": 128.8964,
        "captured_at": "2026-05-30T14:20:11Z"
      },
      {
        "star_id": 9845,
        "sky_color_hex": "#A1C4FD",
        "latitude": 37.7725,
        "longitude": 128.9478,
        "captured_at": "2026-05-30T20:35:00Z"
      }
    ]
  }
}
```

## 4. 예외 처리 정의 (Error Handling)

REST 표준에 맞추어 실패 시 명확한 HTTP 상태 코드와 JSON 메시지를 반환합니다.

- **401 Unauthorized (인증 실패):** JWT 토큰이 없거나 만료된 경우JSON
    
    ```
    { "status": "error", "code": "AUTH_EXPIRED", "message": "인증 토큰이 만료되었습니다. 다시 로그인해주세요." }
    ```
    
- `**400 Bad Request (위치 정보 수집 실패):** 필수 좌표 데이터 누락 또는 위경도 데이터가 유효 범위를 벗어난 경우 ```json { "status": "error", "code": "INVALID_LOCATION", "message": "잘못된 위치 정보 좌표입니다." }`