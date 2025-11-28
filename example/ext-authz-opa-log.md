# Envoy: OPA example

- [Envoy: OPA example](#envoy-opa-example)
  - [Overview](#overview)
    - [1. クライアントからの初期リクエスト (Ingress)](#1-クライアントからの初期リクエスト-ingress)
    - [2. 外部認可 (Ext AuthZ) の実行](#2-外部認可-ext-authz-の実行)
      - [2.1. OPAへの `CheckRequest`](#21-opaへの-checkrequest)
      - [2.2. OPAによるポリシー評価](#22-opaによるポリシー評価)
      - [2.3. OPAからの認可レスポンス](#23-opaからの認可レスポンス)
    - [3. バックエンドサービスへのルーティング](#3-バックエンドサービスへのルーティング)
    - [4. クライアントへの最終レスポンス (Egress)](#4-クライアントへの最終レスポンス-egress)
  - [Logs](#logs)
    - [Envoy](#envoy)
    - [Open Policy Agent](#open-policy-agent)

```bash
$ curl -i -H "Authorization: Bearer test-token" http://localhost:8080/api/test
```

## Overview

```mermaid
sequenceDiagram
    participant C as Client (curl)
    participant E as Envoy Proxy
    participant O as OPA (Ext AuthZ)
    participant S as Echo Server (Backend)

    Note over E: ⏳ Time is 16:02:27.481
    C->>E: TCP Connection (ConnId: 0)
    activate E
    E->>E: New Stream (StreamId: 14364395182449484694)
    C->>E: GET /api/test (Headers)
    Note over E: Ext AuthZ Filter initiates check.
    %% OPA CheckRequest
    Note over E: ⏳ 16:02:27.484
    E->>E: AuthZ Check Stream (StreamId: 321275418739896990)
    E->>O: New TCP Connection (ConnId: 1)
    activate O
    E->>O: gRPC CheckRequest (Method: Authorization/Check)
    Note over O: OPA Query: data.envoy.authz.allow<br>Decision ID: 55665fb1-...<br>Total Decision Time: 2.47ms
    Note over E,O: **Authorization in Progress**
    O-->>E: CheckResponse (gRPC Status: 0 / Success)
    deactivate O
    Note over E: Check Successful (decision=true).
    %% Echo Server Request
    Note over E: ⏳ 16:02:27.497
    E->>S: New TCP Connection (ConnId: 2)
    activate S
    E->>S: GET //test (Cluster: echo-server)
    Note over E: Original Path: /api/test
    S-->>E: HTTP 200 OK (Content-Length: 1641)
    deactivate S
    Note over E: Upstream Service Time: 23ms
    %% Final Response
    Note over E: ⏳ 16:02:27.521
    E-->>C: HTTP 200 OK (Content-Type: application/json)
    deactivate E
    Note over C,E: Connection 0 closed 16:02:28.530
```

このログは、**Envoy Proxy** が **外部認可サービス (External Authorization Service)** として **Open Policy Agent (OPA)** を利用し、その背後にあるバックエンドサービスにリクエストをプロキシする一連の流れを示している

### 1. クライアントからの初期リクエスト (Ingress)

クライアント（`curl`）がEnvoyに対してリクエストを送信します。Envoyはこれを新しい接続とストリームとして受け付けます。

* **リクエスト:** `GET http://localhost:8080/api/test`
* **Envoyログ:**
  * `[2025-11-28 16:02:27.481]... new connection from 127.0.0.1:48524`：クライアント（ソースアドレス `127.0.0.1:48524`）からの新しいTCP接続確立。
  * `[2025-11-28 16:02:27.482]... new stream`：HTTPコネクションマネージャがストリームを確立（`StreamId: 14364395182449484694`）。
  * `[2025-11-28 16:02:27.483]... request headers complete... ':path', '/api/test' ... 'authorization', 'Bearer test-token'`：リクエストヘッダーの解析完了。

| ログタイム (UTC) | エンティティ | ログ内容と解説 | シーケンス対応 |
| -- | -- | -- | -- |
| 16:02:27.481|Envoy|new connection from 127.0.0.1:48524 (ConnId: 0)|Client -> Envoy: TCP接続確立|
| 16:02:27.482|Envoy|new stream (StreamId: 14364395182449484694)|Envoy内部: HTTPストリーム開始|
| 16:02:27.483|Envoy|request headers complete ... /api/test|Client -> Envoy: GETリクエスト送信|

### 2. 外部認可 (Ext AuthZ) の実行

EnvoyのHTTPフィルタチェーンで **Ext AuthZ フィルタ** が動作し、リクエストをバックエンドにルーティングする前に認可チェックを行います。

#### 2.1. OPAへの `CheckRequest`

Envoyは、認可情報を外部の **OPA** サービス（クラスター名 `opa-envoy`）に送信します。これは **gRPC** を使用した `Authorization/Check` リクエストとして実行されます。

* **Envoyログ:**
  * `[2025-11-28 16:02:27.484]... cluster 'opa-envoy' match for URL '/envoy.service.auth.v3.Authorization/Check'`：Ext AuthZのロジックが起動し、`opa-envoy` クラスターへのルーティングを決定。
  * `[2025-11-28 16:02:27.485]... router decoding headers: ... ':path', '/envoy.service.auth.v3.Authorization/Check' ... 'content-type', 'application/grpc'`：これが gRPC の認可リクエストであることを示します。
  * このリクエストは、Envoyが **OPA**（`127.0.0.1:9191`）への新しい接続 (`ConnectionId: 1`) を確立して送信されます。

#### 2.2. OPAによるポリシー評価

OPAはこの `CheckRequest` のボディに含まれる情報（リクエストヘッダー、パスなど）を **Input** として受け取り、設定されたポリシー（Regoコード）を評価します。

* **OPAログ:**
  * `[2025-11-28T16:02:27Z]... "msg":"Executing policy query.","query":"data.envoy.authz.allow"`：Envoy Ext AuthZのデフォルトのクエリパス (`data.envoy.authz.allow`) でポリシー評価を開始。
  * `"input":[[{"type":"string","value":"request"},{"type":"object","value":[[{"type":"string","value":"http"},{"type":"object","value":[[{"type":"string","value":"headers"},{"type":"object","value":[[{"type":"string","value":"authorization"},{"type":"string","value":"Bearer test-token"}]]}]]}]]}]]`：OPAの入力データには、元のリクエストの詳細がJSON形式で含まれていることがわかります。

|ログタイム (UTC)|エンティティ|ログ内容と解説|シーケンス対応|
|-|-|-|-|
| 16:02:27.484|Envoy|cluster 'opa-envoy' match for URL '/.../Authorization/Check' (StreamId: 32127...90)|Envoy内部: OPAへの認可ストリーム開始|
| 16:02:27.485|Envoy|trying to create new connection (ConnId: 1)|Envoy -> OPA: 新しいTCP接続を試行|
| 16:02:27.486|Envoy|ConnId: 1 connected to 127.0.0.1:9191|Envoy -> OPA: gRPC接続確立|
| 16:02:27.487|Envoy|ConnId: 1 encode complete|Envoy -> OPA: gRPC CheckRequest 送信|
| 16:02:27.495|OPA|"""query"":""data.envoy.authz.allow""| ""result"":true"|OPA内部: ポリシー評価、認可成功|
| 16:02:27.496|Envoy|"StreamId: 32127...90 upstream headers complete: ':status'| '200'"|OPA -> Envoy: gRPCレスポンス受信開始|
| 16:02:27.497|Envoy|"ConnId: 1 response complete ... 'grpc-status'| '0'"|OPA -> Envoy: gRPCレスポンス完了（成功）|

#### 2.3. OPAからの認可レスポンス

OPAはポリシー評価の結果を `CheckResponse` としてEnvoyに返します。

* **OPAログ:**
  * `[2025-11-28T16:02:27Z]... "decision":true, ... "msg":"Returning policy decision."`：ポリシー評価の結果、**認可は成功** (許可) となりました。
* **Envoyログ:**
  * `[2025-11-28 16:02:27.497]... response complete ... 'grpc-status', '0'`：gRPCステータスコード `0` は成功を示します。

### 3. バックエンドサービスへのルーティング

認可が成功したため、Envoyは元のリクエストを最終的なバックエンドサービス（ログでは `echo-server`）に転送します。

* **Envoyログ:**
  * `[2025-11-28 16:02:27.497]... cluster 'echo-server' match for URL '/api/test'`：元のパス (`/api/test`) に基づいてバックエンドクラスター `echo-server` へのルーティングを決定。
  * `[2025-11-28 16:02:27.497]... router decoding headers: ... ':path', '//test' ... 'x-envoy-original-path', '/api/test'`：バックエンドへのリクエストヘッダーがエンコードされます。パスが変更されているのは、Envoyの設定によるパスの書き換え（Rewrite）が適用されている可能性があるためです。
  * Envoyはバックエンド（`127.0.0.1:80`）への新しい接続 (`ConnectionId: 2`) を確立してリクエストを送信します。

| ログタイム (UTC)|エンティティ|ログ内容と解説|シーケンス対応|
| -|-|-|-|
| 16:02:27.497|Envoy|cluster 'echo-server' match for URL '/api/test' (StreamId: 14364...94)|Envoy内部: バックエンドへのルーティング決定|
| 16:02:27.497|Envoy|creating a new connection (ConnId: 2)|Envoy -> Backend: 新しいTCP接続を試行|
| 16:02:27.498|Envoy|ConnId: 2 connected to 127.0.0.1:80|Envoy -> Backend: 接続確立|
| 16:02:27.498|Envoy|ConnId: 2 encode complete|Envoy -> Backend: GETリクエスト送信|

### 4. クライアントへの最終レスポンス (Egress)

バックエンドサービスがリクエストを処理し、Envoy経由でクライアントにレスポンスを返します。

* **Envoyログ:**
  * `[2025-11-28 16:02:27.521]... upstream headers complete: end_stream=false ... ':status', '200'`：バックエンドサービスからのレスポンス（`HTTP 200 OK`）を受信。
  * `[2025-11-28 16:02:27.521]... encoding headers via codec (end_stream=false): ':status', '200' ... 'content-length', '1641'`：Envoyがクライアントに向けてレスポンスヘッダーをエンコード。
  * `[2025-11-28T16:02:27.482Z] "GET /api/test HTTP/1.1" 200 - 0 1641 39 23 ...`：アクセスログ。`200` は成功、`39` はダウンストリーム（クライアント）へのレスポンス時間（ミリ秒）、`23` はアップストリーム（バックエンド）へのレスポンス時間（ミリ秒）を示します。

この一連の流れから、このシステムが **APIゲートウェイ** や **サービスメッシュ** の一部として機能し、リクエストがバックエンドに到達する前に **Envoy** によって **OPA** を用いた集中型の認証・認可ポリシーが適用されていることが明確にわかります。

| ログタイム (UTC)|エンティティ|ログ内容と解説|シーケンス対応|
| -|-|-|-|
| 16:02:27.521|Envoy|"StreamId: 14364...94 upstream headers complete: ':status'| '200'"|Backend -> Envoy: HTTP 200 受信|
| 16:02:27.521|Envoy|"StreamId: 14364...94 encoding headers via codec: ':status'| '200'"|Envoy -> Client: HTTP 200 転送開始|
| 16:02:27.522|Envoy|"GET /api/test HTTP/1.1"" 200 ... 39 23"|アクセスログ出力。合計時間 39ms、バックエンド処理時間 23ms。|
| 16:02:28.530|Envoy|ConnId: 0 remote close|Client/Envoy: TCP接続終了|


## Logs

### Envoy

```bash
$ k logs -f envoy-ext-authz-opa-55c4d4794f-r2jmx -c envoy
...
[2025-11-28 16:02:27.481][20][debug][conn_handler] [source/extensions/listener_managers/listener_manager/active_tcp_listener.cc:159] [Tags: "ConnectionId":"0"] new connection from 127.0.0.1:48524
[2025-11-28 16:02:27.482][20][debug][http] [source/common/http/conn_manager_impl.cc:391] [Tags: "ConnectionId":"0"] new stream
[2025-11-28 16:02:27.483][20][debug][http] [source/common/http/conn_manager_impl.cc:1194] [Tags: "ConnectionId":"0","StreamId":"14364395182449484694"] request headers complete (end_stream=true):
':authority', 'localhost:8080'
':path', '/api/test'
':method', 'GET'
'user-agent', 'curl/8.7.1'
'accept', '*/*'
'authorization', 'Bearer test-token'

[2025-11-28 16:02:27.483][20][debug][http] [source/common/http/conn_manager_impl.cc:1177] [Tags: "ConnectionId":"0","StreamId":"14364395182449484694"] request end stream
[2025-11-28 16:02:27.483][20][debug][connection] [./source/common/network/connection_impl.h:98] [Tags: "ConnectionId":"0"] current connecting state: false
[2025-11-28 16:02:27.484][20][debug][router] [source/common/router/router.cc:520] [Tags: "ConnectionId":"0","StreamId":"321275418739896990"] cluster 'opa-envoy' match for URL '/envoy.service.auth.v3.Authorization/Check'
[2025-11-28 16:02:27.485][20][debug][router] [source/common/router/router.cc:732] [Tags: "ConnectionId":"0","StreamId":"321275418739896990"] router decoding headers:
':method', 'POST'
':path', '/envoy.service.auth.v3.Authorization/Check'
':authority', 'opa-envoy'
':scheme', 'http'
'te', 'trailers'
'grpc-timeout', '1000m'
'content-type', 'application/grpc'
'x-envoy-internal', 'true'
'x-forwarded-for', '10.244.0.5'
'x-envoy-expected-rq-timeout-ms', '1000'

[2025-11-28 16:02:27.485][20][debug][pool] [source/common/http/conn_pool_base.cc:78] queueing stream due to no available connections (ready=0 busy=0 connecting=0)
[2025-11-28 16:02:27.485][20][debug][pool] [source/common/conn_pool/conn_pool_base.cc:291] trying to create new connection
[2025-11-28 16:02:27.485][20][debug][pool] [source/common/conn_pool/conn_pool_base.cc:145] creating a new connection (connecting=0)
[2025-11-28 16:02:27.485][20][debug][http2] [source/common/http/http2/codec_impl.cc:1617] [Tags: "ConnectionId":"1"] updating connection-level initial window size to 268435456
[2025-11-28 16:02:27.485][20][debug][connection] [./source/common/network/connection_impl.h:98] [Tags: "ConnectionId":"1"] current connecting state: true
[2025-11-28 16:02:27.485][20][debug][client] [source/common/http/codec_client.cc:57] [Tags: "ConnectionId":"1"] connecting
[2025-11-28 16:02:27.485][20][debug][connection] [source/common/network/connection_impl.cc:1009] [Tags: "ConnectionId":"1"] connecting to 127.0.0.1:9191
[2025-11-28 16:02:27.486][20][debug][connection] [source/common/network/connection_impl.cc:1028] [Tags: "ConnectionId":"1"] connection in progress
[2025-11-28 16:02:27.486][20][debug][connection] [source/common/network/connection_impl.cc:746] [Tags: "ConnectionId":"1"] connected
[2025-11-28 16:02:27.486][20][debug][client] [source/common/http/codec_client.cc:88] [Tags: "ConnectionId":"1"] connected
[2025-11-28 16:02:27.486][20][debug][pool] [source/common/conn_pool/conn_pool_base.cc:328] [Tags: "ConnectionId":"1"] attaching to next stream
[2025-11-28 16:02:27.486][20][debug][pool] [source/common/conn_pool/conn_pool_base.cc:182] [Tags: "ConnectionId":"1"] creating stream
[2025-11-28 16:02:27.486][20][debug][router] [source/common/router/upstream_request.cc:579] [Tags: "ConnectionId":"0","StreamId":"321275418739896990"] pool ready
[2025-11-28 16:02:27.487][20][debug][client] [source/common/http/codec_client.cc:141] [Tags: "ConnectionId":"1"] encode complete
[2025-11-28 16:02:27.496][20][debug][router] [source/common/router/router.cc:1493] [Tags: "ConnectionId":"0","StreamId":"321275418739896990"] upstream headers complete: end_stream=false
[2025-11-28 16:02:27.497][20][debug][http] [source/common/http/async_client_impl.cc:141] async http request response headers (end_stream=false):
':status', '200'
'content-type', 'application/grpc'
'x-envoy-upstream-service-time', '10'

[2025-11-28 16:02:27.497][20][debug][client] [source/common/http/codec_client.cc:128] [Tags: "ConnectionId":"1"] response complete
[2025-11-28 16:02:27.497][20][debug][pool] [source/common/conn_pool/conn_pool_base.cc:215] [Tags: "ConnectionId":"1"] destroying stream: 0 remaining
[2025-11-28 16:02:27.497][20][debug][http] [source/common/http/async_client_impl.cc:168] async http request response trailers:
'grpc-status', '0'
'grpc-message', ''

[2025-11-28 16:02:27.497][20][debug][router] [source/common/router/router.cc:520] [Tags: "ConnectionId":"0","StreamId":"14364395182449484694"] cluster 'echo-server' match for URL '/api/test'
[2025-11-28 16:02:27.497][20][debug][router] [source/common/router/router.cc:732] [Tags: "ConnectionId":"0","StreamId":"14364395182449484694"] router decoding headers:
':authority', 'localhost:8080'
':path', '//test'
':method', 'GET'
':scheme', 'http'
'user-agent', 'curl/8.7.1'
'accept', '*/*'
'authorization', 'Bearer test-token'
'x-forwarded-proto', 'http'
'x-request-id', '1b07886b-9d46-4a9a-b3ba-3d24b1baec94'
'x-envoy-expected-rq-timeout-ms', '15000'
'x-envoy-original-path', '/api/test'

[2025-11-28 16:02:27.497][20][debug][pool] [source/common/http/conn_pool_base.cc:78] queueing stream due to no available connections (ready=0 busy=0 connecting=0)
[2025-11-28 16:02:27.497][20][debug][pool] [source/common/conn_pool/conn_pool_base.cc:291] trying to create new connection
[2025-11-28 16:02:27.497][20][debug][pool] [source/common/conn_pool/conn_pool_base.cc:145] creating a new connection (connecting=0)
[2025-11-28 16:02:27.497][20][debug][connection] [./source/common/network/connection_impl.h:98] [Tags: "ConnectionId":"2"] current connecting state: true
[2025-11-28 16:02:27.497][20][debug][client] [source/common/http/codec_client.cc:57] [Tags: "ConnectionId":"2"] connecting
[2025-11-28 16:02:27.497][20][debug][connection] [source/common/network/connection_impl.cc:1009] [Tags: "ConnectionId":"2"] connecting to 127.0.0.1:80
[2025-11-28 16:02:27.497][20][debug][connection] [source/common/network/connection_impl.cc:1028] [Tags: "ConnectionId":"2"] connection in progress
[2025-11-28 16:02:27.498][20][debug][http2] [source/common/http/http2/codec_impl.cc:1362] [Tags: "ConnectionId":"1"] stream 1 closed: 0
[2025-11-28 16:02:27.498][20][debug][http2] [source/common/http/http2/codec_impl.cc:1426] [Tags: "ConnectionId":"1"] Recouping 0 bytes of flow control window for stream 1.
[2025-11-28 16:02:27.498][20][debug][connection] [source/common/network/connection_impl.cc:746] [Tags: "ConnectionId":"2"] connected
[2025-11-28 16:02:27.498][20][debug][client] [source/common/http/codec_client.cc:88] [Tags: "ConnectionId":"2"] connected
[2025-11-28 16:02:27.498][20][debug][pool] [source/common/conn_pool/conn_pool_base.cc:328] [Tags: "ConnectionId":"2"] attaching to next stream
[2025-11-28 16:02:27.498][20][debug][pool] [source/common/conn_pool/conn_pool_base.cc:182] [Tags: "ConnectionId":"2"] creating stream
[2025-11-28 16:02:27.498][20][debug][router] [source/common/router/upstream_request.cc:579] [Tags: "ConnectionId":"0","StreamId":"14364395182449484694"] pool ready
[2025-11-28 16:02:27.498][20][debug][client] [source/common/http/codec_client.cc:141] [Tags: "ConnectionId":"2"] encode complete
[2025-11-28 16:02:27.521][20][debug][router] [source/common/router/router.cc:1493] [Tags: "ConnectionId":"0","StreamId":"14364395182449484694"] upstream headers complete: end_stream=false
[2025-11-28 16:02:27.521][20][debug][http] [source/common/http/conn_manager_impl.cc:1863] [Tags: "ConnectionId":"0","StreamId":"14364395182449484694"] encoding headers via codec (end_stream=false):
':status', '200'
'content-type', 'application/json; charset=utf-8'
'content-length', '1641'
'etag', 'W/"669-3UkbKSnCB2XwUVjIiQPavJ906E8"'
'date', 'Fri, 28 Nov 2025 16:02:27 GMT'
'x-envoy-upstream-service-time', '23'
'server', 'envoy'

[2025-11-28 16:02:27.522][20][debug][client] [source/common/http/codec_client.cc:128] [Tags: "ConnectionId":"2"] response complete
[2025-11-28 16:02:27.522][20][debug][http] [source/common/http/conn_manager_impl.cc:1968] [Tags: "ConnectionId":"0","StreamId":"14364395182449484694"] Codec completed encoding stream.
[2025-11-28 16:02:27.522][20][debug][pool] [source/common/http/http1/conn_pool.cc:53] [Tags: "ConnectionId":"2"] response complete
[2025-11-28T16:02:27.482Z] "GET /api/test HTTP/1.1" 200 - 0 1641 39 23 "-" "curl/8.7.1" "1b07886b-9d46-4a9a-b3ba-3d24b1baec94" "localhost:8080" "127.0.0.1:80"
[2025-11-28 16:02:27.522][20][debug][pool] [source/common/conn_pool/conn_pool_base.cc:215] [Tags: "ConnectionId":"2"] destroying stream: 0 remaining
[2025-11-28 16:02:28.530][20][debug][connection] [source/common/network/connection_impl.cc:714] [Tags: "ConnectionId":"0"] remote close
[2025-11-28 16:02:28.530][20][debug][connection] [source/common/network/connection_impl.cc:278] [Tags: "ConnectionId":"0"] closing socket: 0
```

### Open Policy Agent

```bash
$ k logs -f envoy-ext-authz-opa-55c4d4794f-r2jmx -c opa
...
{"headers":{"Accept-Ranges":["bytes"],"Access-Control-Allow-Origin":["*"],"Access-Control-Expose-Headers":["ETag, Link, Location, Retry-After, X-GitHub-OTP, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Used, X-RateLimit-Resource, X-RateLimit-Reset, X-OAuth-Scopes, X-Accepted-OAuth-Scopes, X-Poll-Interval, X-GitHub-Media-Type, X-GitHub-SSO, X-GitHub-Request-Id, Deprecation, Sunset"],"Cache-Control":["public, max-age=60, s-maxage=60"],"Content-Security-Policy":["default-src 'none'"],"Content-Type":["application/json; charset=utf-8"],"Date":["Fri, 28 Nov 2025 16:01:21 GMT"],"Etag":["W/\"e71c6915e515a8c4f88a6cca997b000e44529ac1a2552af98bef5806f1ae7699\""],"Last-Modified":["Wed, 26 Nov 2025 13:24:08 GMT"],"Referrer-Policy":["origin-when-cross-origin, strict-origin-when-cross-origin"],"Server":["github.com"],"Strict-Transport-Security":["max-age=31536000; includeSubdomains; preload"],"Vary":["Accept,Accept-Encoding, Accept, X-Requested-With"],"X-Content-Type-Options":["nosniff"],"X-Frame-Options":["deny"],"X-Github-Api-Version-Selected":["2022-11-28"],"X-Github-Media-Type":["github.v3; format=json"],"X-Github-Request-Id":["ED90:7362A:81C099:A05EBB:6929C764"],"X-Ratelimit-Limit":["60"],"X-Ratelimit-Remaining":["58"],"X-Ratelimit-Reset":["1764348701"],"X-Ratelimit-Resource":["core"],"X-Ratelimit-Used":["2"],"X-Xss-Protection":["0"]},"level":"debug","method":"GET","msg":"Received response.","status":"200 OK","time":"2025-11-28T16:01:40Z","url":"https://api.github.com/repos/open-policy-agent/opa/releases/latest"}
{"current_version":"1.11.0","level":"debug","msg":"OPA is up to date.","time":"2025-11-28T16:01:40Z"}
{"decision-id":"55665fb1-9f83-4899-94c0-6c276d274388","level":"debug","msg":"no content-type header supplied, performing no body parsing","time":"2025-11-28T16:02:27Z"}
{"input":[[{"type":"string","value":"attributes"},{"type":"object","value":[[{"type":"string","value":"destination"},{"type":"object","value":[[{"type":"string","value":"address"},{"type":"object","value":[[{"type":"string","value":"socketAddress"},{"type":"object","value":[[{"type":"string","value":"address"},{"type":"string","value":"127.0.0.1"}],[{"type":"string","value":"portValue"},{"type":"number","value":8080}]]}]]}]]}],[{"type":"string","value":"metadataContext"},{"type":"object","value":[]}],[{"type":"string","value":"request"},{"type":"object","value":[[{"type":"string","value":"http"},{"type":"object","value":[[{"type":"string","value":"headers"},{"type":"object","value":[[{"type":"string","value":":authority"},{"type":"string","value":"localhost:8080"}],[{"type":"string","value":":method"},{"type":"string","value":"GET"}],[{"type":"string","value":":path"},{"type":"string","value":"/api/test"}],[{"type":"string","value":":scheme"},{"type":"string","value":"http"}],[{"type":"string","value":"accept"},{"type":"string","value":"*/*"}],[{"type":"string","value":"authorization"},{"type":"string","value":"Bearer test-token"}],[{"type":"string","value":"user-agent"},{"type":"string","value":"curl/8.7.1"}],[{"type":"string","value":"x-forwarded-proto"},{"type":"string","value":"http"}],[{"type":"string","value":"x-request-id"},{"type":"string","value":"1b07886b-9d46-4a9a-b3ba-3d24b1baec94"}]]}],[{"type":"string","value":"host"},{"type":"string","value":"localhost:8080"}],[{"type":"string","value":"id"},{"type":"string","value":"14364395182449484694"}],[{"type":"string","value":"method"},{"type":"string","value":"GET"}],[{"type":"string","value":"path"},{"type":"string","value":"/api/test"}],[{"type":"string","value":"protocol"},{"type":"string","value":"HTTP/1.1"}],[{"type":"string","value":"scheme"},{"type":"string","value":"http"}]]}],[{"type":"string","value":"time"},{"type":"object","value":[[{"type":"string","value":"nanos"},{"type":"number","value":482449000}],[{"type":"string","value":"seconds"},{"type":"number","value":1764345747}]]}]]}],[{"type":"string","value":"source"},{"type":"object","value":[[{"type":"string","value":"address"},{"type":"object","value":[[{"type":"string","value":"socketAddress"},{"type":"object","value":[[{"type":"string","value":"address"},{"type":"string","value":"127.0.0.1"}],[{"type":"string","value":"portValue"},{"type":"number","value":48524}]]}]]}]]}]]}],[{"type":"string","value":"parsed_body"},{"type":"null","value":{}}],[{"type":"string","value":"parsed_path"},{"type":"array","value":[{"type":"string","value":"api"},{"type":"string","value":"test"}]}],[{"type":"string","value":"parsed_query"},{"type":"object","value":[]}],[{"type":"string","value":"truncated_body"},{"type":"boolean","value":false}],[{"type":"string","value":"version"},{"type":"object","value":[[{"type":"string","value":"encoding"},{"type":"string","value":"protojson"}],[{"type":"string","value":"ext_authz"},{"type":"string","value":"v3"}]]}]],"level":"debug","msg":"Executing policy query.","query":"data.envoy.authz.allow","time":"2025-11-28T16:02:27Z","txn":3}
{"decision":true,"decision-id":"55665fb1-9f83-4899-94c0-6c276d274388","dry-run":false,"err":null,"level":"debug","metrics":{"timer_rego_query_compile_ns":244583,"timer_rego_query_eval_ns":222583,"timer_server_handler_ns":0},"msg":"Returning policy decision.","query":"data.envoy.authz.allow","time":"2025-11-28T16:02:27Z","total_decision_time":2473208,"txn":3}
{"decision_id":"55665fb1-9f83-4899-94c0-6c276d274388","input":{"attributes":{"destination":{"address":{"socketAddress":{"address":"127.0.0.1","portValue":8080}}},"metadataContext":{},"request":{"http":{"headers":{":authority":"localhost:8080",":method":"GET",":path":"/api/test",":scheme":"http","accept":"*/*","authorization":"Bearer test-token","user-agent":"curl/8.7.1","x-forwarded-proto":"http","x-request-id":"1b07886b-9d46-4a9a-b3ba-3d24b1baec94"},"host":"localhost:8080","id":"14364395182449484694","method":"GET","path":"/api/test","protocol":"HTTP/1.1","scheme":"http"},"time":{"nanos":482449000,"seconds":1764345747}},"source":{"address":{"socketAddress":{"address":"127.0.0.1","portValue":48524}}}},"parsed_body":null,"parsed_path":["api","test"],"parsed_query":{},"truncated_body":false,"version":[[{"type":"string","value":"encoding"},{"type":"string","value":"protojson"}],[{"type":"string","value":"ext_authz"},{"type":"string","value":"v3"}]]},"labels":{"id":"296d7e57-e015-4a5b-b15c-960397062b9c","version":"1.11.0"},"level":"info","metrics":{"timer_rego_query_compile_ns":244583,"timer_rego_query_eval_ns":222583,"timer_server_handler_ns":2478750},"msg":"Decision Log","path":"envoy/authz/allow","result":true,"time":"2025-11-28T16:02:27Z","timestamp":"2025-11-28T16:02:27.495578005Z","type":"openpolicyagent.org/decision_logs"}
```
