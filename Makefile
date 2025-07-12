# mfacat Makefile
# 初期セットアップを自動化するためのMakefile

.PHONY: help install setup install-deps install-jq install-aws-cli install-1password-cli

# デフォルトターゲット
help:
	@echo "mfacat セットアップ用 Makefile"
	@echo ""
	@echo "利用可能なターゲット:"
	@echo "  setup        - 完全なセットアップ（推奨）"
	@echo "  install      - mfacat.shを~/.aws/にインストール"
	@echo "  install-deps - 依存関係をインストール"
	@echo "  install-jq   - jqをインストール"
	@echo "  install-aws-cli - AWS CLIをインストール"
	@echo "  install-1password-cli - 1Password CLIをインストール"
	@echo "  help         - このヘルプを表示"

# 完全なセットアップ（推奨）
setup: install-deps install
	@echo "✅ セットアップが完了しました！"
	@echo ""
	@echo "使用方法:"
	@echo "  ~/.aws/mfacat.sh --profile myprofile --token 123456 --serial_number arn:aws:iam::123456789012:mfa/user"
	@echo "  ~/.aws/mfacat.sh --profile myprofile --op \"AWS | MyAccount\" --serial_number arn:aws:iam::123456789012:mfa/user"

# mfacat.shを~/.aws/にインストール
install:
	@echo "📦 mfacat.shをインストール中..."
	@mkdir -p ~/.aws
	@cp mfacat.sh ~/.aws/mfacat.sh
	@chmod +x ~/.aws/mfacat.sh
	@echo "✅ mfacat.shが ~/.aws/mfacat.sh にインストールされました"

# 依存関係をインストール
install-deps: install-jq
	@echo "✅ 依存関係のインストールが完了しました"

# jqをインストール
install-jq:
	@echo "🔧 jqをインストール中..."
	@if command -v jq >/dev/null 2>&1; then \
		echo "✅ jqは既にインストールされています"; \
	else \
		if [[ "$(uname)" == "Darwin" ]]; then \
			if command -v brew >/dev/null 2>&1; then \
				brew install jq; \
			else \
				echo "❌ Homebrewがインストールされていません。https://brew.sh/ からインストールしてください"; \
				exit 1; \
			fi; \
		elif [[ "$(uname)" == "Linux" ]]; then \
			if command -v apt-get >/dev/null 2>&1; then \
				sudo apt-get update && sudo apt-get install -y jq; \
			elif command -v yum >/dev/null 2>&1; then \
				sudo yum install -y jq; \
			elif command -v dnf >/dev/null 2>&1; then \
				sudo dnf install -y jq; \
			else \
				echo "❌ サポートされていないパッケージマネージャーです。手動でjqをインストールしてください"; \
				exit 1; \
			fi; \
		else \
			echo "❌ サポートされていないOSです。手動でjqをインストールしてください"; \
			exit 1; \
		fi; \
		echo "✅ jqがインストールされました"; \
	fi

# AWS CLIをインストール
install-aws-cli:
	@echo "🔧 AWS CLIをインストール中..."
	@if command -v aws >/dev/null 2>&1; then \
		echo "✅ AWS CLIは既にインストールされています"; \
	else \
		if [[ "$(uname)" == "Darwin" ]]; then \
			if command -v brew >/dev/null 2>&1; then \
				brew install awscli; \
			else \
				echo "❌ Homebrewがインストールされていません。https://brew.sh/ からインストールしてください"; \
				exit 1; \
			fi; \
		elif [[ "$(uname)" == "Linux" ]]; then \
			echo "📥 AWS CLIをダウンロード中..."; \
			curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"; \
			unzip awscliv2.zip; \
			sudo ./aws/install; \
			rm -rf aws awscliv2.zip; \
		else \
			echo "❌ サポートされていないOSです。手動でAWS CLIをインストールしてください"; \
			echo "   https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"; \
			exit 1; \
		fi; \
		echo "✅ AWS CLIがインストールされました"; \
	fi

# 1Password CLIをインストール
install-1password-cli:
	@echo "🔧 1Password CLIをインストール中..."
	@if command -v op >/dev/null 2>&1; then \
		echo "✅ 1Password CLIは既にインストールされています"; \
	else \
		if [[ "$(uname)" == "Darwin" ]]; then \
			if command -v brew >/dev/null 2>&1; then \
				brew install --cask 1password-cli; \
			else \
				echo "❌ Homebrewがインストールされていません。https://brew.sh/ からインストールしてください"; \
				exit 1; \
			fi; \
		elif [[ "$(uname)" == "Linux" ]]; then \
			echo "📥 1Password CLIをダウンロード中..."; \
			curl -sS https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg; \
			echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | sudo tee /etc/apt/sources.list.d/1password.list; \
			sudo apt-get update && sudo apt-get install -y 1password-cli; \
		else \
			echo "❌ サポートされていないOSです。手動で1Password CLIをインストールしてください"; \
			echo "   https://developer.1password.com/docs/cli/get-started/"; \
			exit 1; \
		fi; \
		echo "✅ 1Password CLIがインストールされました"; \
	fi

# アンインストール
uninstall:
	@echo "🗑️  mfacatをアンインストール中..."
	@rm -f ~/.aws/mfacat.sh
	@echo "✅ mfacatがアンインストールされました"
	@echo "注意: 依存関係（jq、AWS CLI、1Password CLI）は手動で削除してください" 