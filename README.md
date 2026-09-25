# 早押しクイズ 早押しボタンサイト（Supabase版）

## 構成
- `index.html` … 参加者用。名前登録後、ボタンのみ表示
- `admin.html` … 管理者用。参加者一覧／ボタンON-OFF／リセット／結果表示／QRコード
- `schema.sql` … Supabaseに投入するテーブル・RLSポリシー・RPC関数一式
- Supabase Realtime（Postgres Changes）でリアルタイム同期。サインイン不要・匿名アクセス可

## セットアップ

### 1. Supabaseプロジェクトの準備
1. 既存プロジェクト、または新規プロジェクトを用意
2. SQL Editor で `schema.sql` の内容をそのまま全文実行
3. Project Settings > API から `URL` と `anon public key` を取得し `supabase-config.js` に記入
4. Project Settings > API > Realtime（または Database > Replication）で `rounds` `participants` `presses` `quiz_state` が配信対象に入っていることを確認（`schema.sql` 内の `alter publication` で自動設定済みのはず）

### 2. デプロイ（Vercel）
```
npm i -g vercel
cd quiz-buzzer
vercel --prod
```
静的サイトなのでビルド設定不要（Framework: Other）。

### 3. 使い方
1. `admin.html` を管理者が開く（表示されたQRコードが参加者用URL）
2. 参加者はQRを読み取り、名前を入力して参加
3. 管理者が「ボタン: OFF」→クリックでON、参加者がボタンを押せるようになる
4. 押した順に管理画面へ 順位・タイム（サーバー側 `now()` 基準の経過秒 — 端末間クロックズレの影響を受けない）が表示
5. 次の問題に進む際は「押下リセット（次の問題へ）」— 参加者はそのまま、押下状態だけ初期化
6. イベント終了・別グループで最初からやり直す際は「参加者を全リセット」

## セキュリティ設計
- `presses`（押下記録）テーブルへの直接 INSERT はRLSで禁止。書き込みは `press_buzzer` RPC（`security definer`）経由のみに限定し、内部で行ロック（`FOR UPDATE`）により押下順を原子的に確定させている。
- `participants` / `rounds` は anon ロールに読み書きを開放（内輪イベント想定の簡易運用）。荒らし対策を厳密にするなら Supabase Anonymous Auth を導入し、`auth.uid()` ベースのポリシーに置き換える。

## 既知の制約
- 多重ルーム非対応（単一セッション設計）。並行イベント運用が必要なら `rounds` 等に `room_id` を追加する改修が必要。
