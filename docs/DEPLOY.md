# 친구들에게 열어주기 (무료)

게임 서버는 WebSocket 을 계속 붙들고 있어야 해서 무료 호스팅과 궁합이 나쁘다.
그래서 **서버는 내 PC 에서 돌리고 터널로 노출**하고, **웹페이지만 정적 호스팅**한다.

```
친구 브라우저
   │
   ├─ 페이지  ──▶  Cloudflare Pages   (무료, 상시)
   │
   └─ 게임서버 ──▶  Cloudflare Tunnel ──▶ 내 PC :2567
```

**공유기 포트를 열지 않는다.** 터널은 내 PC 가 밖으로 연결을 거는 방식이라
홈 네트워크가 노출되지 않는다. 포트포워딩은 절대 쓰지 말 것.

---

## 1. cloudflared 설치 (최초 1회)

```bash
winget install --id Cloudflare.cloudflared
```

설치 후 **새 터미널**을 열어야 PATH 가 잡힌다.

## 2. 웹페이지를 Cloudflare Pages 에 올리기 (최초 1회)

```bash
npm run build
```

`packages/client/dist` 가 만들어진다. 올리는 방법은 두 가지다.

**A. 대시보드에 드래그앤드롭** — 가장 간단하다.
[Cloudflare Pages](https://dash.cloudflare.com) → Workers & Pages → Create →
Pages → Upload assets → `dist` 폴더를 통째로 끌어다 놓는다.

**B. CLI**

```bash
npx wrangler pages deploy packages/client/dist --project-name mmorpg
```

둘 다 `https://<프로젝트>.pages.dev` 주소를 준다. **이 주소는 안 바뀐다.**

> 에셋(6MB)이 함께 올라간다. Pages 무료 플랜은 파일 2만 개 / 25MB per file 이라
> 여유가 충분하다.

## 3. 놀 때마다: 서버 + 터널 켜기

터미널 두 개.

```bash
npm run server
```

```bash
npm run tunnel https://내프로젝트.pages.dev
```

두 번째 명령이 이런 걸 출력한다:

```
  서버 주소   wss://random-words-1234.trycloudflare.com
  공유 링크   https://내프로젝트.pages.dev/?server=wss://random-words-1234.trycloudflare.com
```

**공유 링크를 친구에게 보내면 끝이다.**

## 왜 링크에 서버 주소가 붙는가

무료 터널은 켤 때마다 주소가 바뀐다. 서버 주소를 빌드에 박아두면
터널을 켤 때마다 다시 빌드해서 다시 배포해야 한다.

그래서 클라이언트는 `?server=` 쿼리로 주소를 받고 `localStorage` 에 저장한다.
친구는 **처음 한 번만** 링크로 들어오면 되고, 그 다음부터는
`https://내프로젝트.pages.dev` 만으로 접속된다 — 터널 주소가 바뀌기 전까지는.

주소가 바뀌면 새 공유 링크를 다시 보내면 된다.

## 주의할 점

- **HTTPS 페이지에서는 `wss://` 만 붙는다.** `ws://` 로 접속하면 브라우저가
  혼합 콘텐츠로 조용히 막는다. 스크립트가 자동으로 `wss://` 로 변환하고,
  잘못된 조합이면 화면에 경고를 띄운다.
- 내 PC 를 끄거나 절전으로 들어가면 게임이 끊긴다.
- 집 인터넷 **업로드** 속도를 나눠 쓴다. 동접 몇 명 수준에서는 문제없다.

## 다음 단계 (상시 운영이 필요해지면)

| | 비용 | 특징 |
|---|---|---|
| Render 무료 | 0 | 15분 놀면 잠들고 깨는 데 1분 |
| Fly.io / Railway | 월 $5~ | 상시 구동 |
| Oracle Cloud Always Free | 0 | 영구 무료지만 가입·용량 확보가 까다롭다 |

서버가 Node 프로세스 하나라 옮기는 비용은 크지 않다.
