# mfacat - AWS MFA Token Management Tool

AWS MFAトークン管理ツールです。AWS CLIでMFA（多要素認証）を使用する際の認証情報を簡単に取得・管理できます。

## 概要

このツールは以下の機能を提供します：

- **MFAトークンの取得**: 6桁のMFAトークンまたは1PasswordからOTPを取得
- **セッショントークンの取得**: AWS STSから一時的な認証情報を取得
- **認証情報のキャッシュ**: 有効期限内は再認証不要
- **JSON形式での出力**: 他のツールとの連携が容易
- **自動認証設定**: `~/.aws/config`での`credential_process`設定により、AWS CLIやSDKでの自動認証

## 使用シーン

- AWS CLIでMFA認証が必要な環境での作業
- CI/CDパイプラインでのAWS認証
- 複数のAWSアカウントの管理
- 1Passwordとの連携によるセキュアな認証
- アプリケーションコードでのMFA認証付きAWS利用

## 前提条件

- AWS CLI
- jq (JSON処理ツール)
- 1Password CLI (op) - `--op`オプションを使用する場合のみ必要

## インストール

### 自動インストール（推奨）

```bash
# 完全なセットアップ（依存関係 + mfacat.shのインストール）
make setup

# または個別にインストール
make install-deps  # 依存関係のみ
make install       # mfacat.shのみ
```

### 手動インストール

```bash
# jqのインストール (macOS)
brew install jq

# jqのインストール (Ubuntu/Debian)
sudo apt-get install jq

# jqのインストール (CentOS/RHEL)
sudo yum install jq

# mfacat.shを~/.aws/にコピー
mkdir -p ~/.aws
cp mfacat.sh ~/.aws/mfacat.sh
chmod +x ~/.aws/mfacat.sh
```

**注意**: インストール後は `~/.aws/mfacat.sh` として実行してください。

## 使用方法

```bash
# 基本的な使用方法（6桁のMFAトークンを直接指定）
~/.aws/mfacat.sh --profile myprofile --token 123456 --serial_number arn:aws:iam::123456789012:mfa/user

# 1PasswordからOTPを取得する場合
~/.aws/mfacat.sh --profile myprofile --op "AWS | MyAccount" --serial_number arn:aws:iam::123456789012:mfa/user

# ヘルプを表示
~/.aws/mfacat.sh --help
```

**注意**: `make setup`でインストールした場合、`~/.aws/mfacat.sh`として実行できます。

## 自動認証設定（推奨）

このツールの最大の利点は、`~/.aws/config`に設定することで、認証情報の管理を自動化できることです。

### 従来の方法の問題点

従来は以下の手順が必要でした：

1. `aws sts get-session-token`を実行
2. 取得した認証情報を`~/.aws/credentials`に手動で書き込み
3. セッショントークンの有効期限（通常1時間）が切れるたびに上記を繰り返し

### このツールによる解決

`~/.aws/config`に以下のように設定することで、認証情報の取得・更新を自動化できます：

```ini
[profile myprofile]
region = ap-northeast-1
output = json
credential_process = ~/.aws/mfacat.sh --profile myprofile --op "AWS | MyAccount" --serial_number arn:aws:iam::123456789012:mfa/user
```

### 設定後の利点

- **AWS CLI**: `aws s3 ls --profile myprofile`のように、通常通りコマンドを実行
- **アプリケーションコード**: AWS SDKが自動的に認証情報を取得・更新
- **認証情報の管理**: ユーザーが意識する必要なし
- **セキュリティ**: 1Passwordとの連携でOTPを自動取得

### 設定方法

1. **`~/.aws/config`ファイルを編集**
   ```bash
   # ファイルが存在しない場合は作成
   mkdir -p ~/.aws
   touch ~/.aws/config
   
   # エディタで編集
   nano ~/.aws/config
   # または
   vim ~/.aws/config
   ```

2. **プロファイル設定を追加**
   ```ini
   [profile myprofile]
   region = ap-northeast-1
   output = json
   credential_process = ~/.aws/mfacat.sh --profile myprofile --op "AWS | MyAccount" --serial_number arn:aws:iam::123456789012:mfa/user
   ```

### 設定例

```ini
# 1Passwordを使用する場合
[profile production]
region = ap-northeast-1
output = json
credential_process = ~/.aws/mfacat.sh --profile production --op "AWS | Production" --serial_number arn:aws:iam::123456789012:mfa/user

# 手動でトークンを入力する場合
[profile staging]
region = ap-northeast-1
output = json
credential_process = ~/.aws/mfacat.sh --profile staging --token 123456 --serial_number arn:aws:iam::123456789012:mfa/user
```

### 設定項目の説明

- `[profile myprofile]`: プロファイル名（任意の名前）
- `region`: AWSリージョン
- `output`: 出力形式（json, text, table）
- `credential_process`: 認証情報を取得するコマンド

### 設定後の使用方法

```bash
# AWS CLIでの使用
aws s3 ls --profile myprofile
aws ec2 describe-instances --profile myprofile

# 環境変数での使用
export AWS_PROFILE=myprofile
aws s3 ls
```

### 注意事項

- `credential_process`で指定するコマンドは、JSON形式で認証情報を出力する必要があります
- 1Passwordを使用する場合は、事前に`op signin`でログインしておく必要があります
- MFAシリアル番号は、AWS IAMコンソールの「セキュリティ認証情報」から確認できます

## オプション

- `--profile`: AWSプロファイル名（デフォルト: default）
- `--token`: 6桁のMFAトークン（`--op`が指定されていない場合は必須）
- `--op`: 1Passwordのアイテム名（`--token`の代わりに使用）
- `--serial_number`: MFAシリアル番号（必須）
- `--help`: ヘルプを表示

**注意**: `--token`と`--op`は同時に指定できません。どちらか一方を指定してください。

## 設定ファイル

認証情報は `~/.aws/mfacat` にTOML形式でキャッシュされます（実行ファイルとは別のファイルです）：

```toml
[myprofile]
aws_access_key_id = "AKIA..."
aws_secret_access_key = "..."
aws_session_token = "..."
expiration = "2025-07-01T03:53:42Z"
```

## 機能

- **AWS MFAトークンの取得**: 6桁のMFAトークンまたは1PasswordからOTPを取得
- **認証情報のキャッシュ**: 有効期限内は再認証不要（`~/.aws/mfacat`に保存）
- **1Passwordとの連携**: `--op`オプションで1PasswordからOTPを自動取得
- **6桁MFAトークンの直接指定**: `--token`オプションで手動入力
- **JSON形式での出力**: 他のツールとの連携が容易
- **自動認証設定**: `~/.aws/config`での`credential_process`設定により、AWS CLIやSDKでの自動認証

## アンインストール

```bash
make uninstall
```

## 参考リンク

- [1Password CLI Documentation](https://developer.1password.com/docs/cli/get-started/)
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [jq Documentation](https://stedolan.github.io/jq/)