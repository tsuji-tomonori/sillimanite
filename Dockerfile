FROM ubuntu:24.10

# フロントエンドの対話を抑制
ENV DEBIAN_FRONTEND=noninteractive

# -------------------------------------------------------------
# 1. ベースとなるパッケージをインストール
# -------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    sudo \
    curl \
    zip \
    unzip \
    jq \
    software-properties-common \
    gnupg \
    lsb-release \
    ca-certificates \
    apt-transport-https \
    build-essential \
    git \
    zsh \
    openssl \
    libssl-dev \
    libffi-dev \
    python3-dev \
    python3-pip \
    python3-venv \
    bsdutils \
    vim \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------
# 2. Docker CLI & Docker Compose plugin のインストール
# -------------------------------------------------------------
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin

# -------------------------------------------------------------
# 3. Java (Amazon Corretto 17) のインストール
#   - 必要に応じてバージョン番号を変更してください
# -------------------------------------------------------------
ENV JAVA_VERSION=17
RUN curl -fsSL https://apt.corretto.aws/corretto.key | gpg --dearmor | tee /usr/share/keyrings/corretto-key.gpg > /dev/null \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/corretto-key.gpg] https://apt.corretto.aws stable main" \
    | tee /etc/apt/sources.list.d/corretto.list \
    && apt-get update \
    && apt-get install -y java-${JAVA_VERSION}-amazon-corretto-jdk

# -------------------------------------------------------------
# 4. Golang のインストール
#   - 必要に応じてバージョン番号を変更してください
# -------------------------------------------------------------
ENV GO_VERSION=1.20.6
RUN curl -OL https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz \
    && rm go${GO_VERSION}.linux-amd64.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# -------------------------------------------------------------
# 5. pyenv のインストール
#   - 必要に応じてバージョン番号を変更してください
# -------------------------------------------------------------
ENV PYTHON_VERSION=3.13
RUN apt-get update && apt-get install -y \
    make build-essential libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev \
    libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev \
    && rm -rf /var/lib/apt/lists/*

ENV PYENV_ROOT=/root/.pyenv
ENV PATH="${PYENV_ROOT}/bin:${PATH}"

# pyenv をクローンしてビルド (基本的な設定)
RUN git clone https://github.com/pyenv/pyenv.git "$PYENV_ROOT" \
    && cd "$PYENV_ROOT" \
    && src/configure \
    && make -C src

# インストールしてグローバルに設定
RUN pyenv install "$PYTHON_VERSION" \
    && pyenv global "$PYTHON_VERSION"

# pyenv の shims にパスを通す
ENV PATH="${PYENV_ROOT}/shims:${PATH}"

# -------------------------------------------------------------
# 6. Node.js のインストール
#   - 必要に応じてバージョン番号を変更してください
# -------------------------------------------------------------
ENV NODE_VERSION=22
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash - \
    && . ~/.nvm/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm current

# -------------------------------------------------------------
# 7. AWS CLI (v2) のインストール
# -------------------------------------------------------------
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# -------------------------------------------------------------
# 8. AWS SAM CLI のインストール
#   - pyenv で利用している Python でインストール
# -------------------------------------------------------------
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir aws-sam-cli

# -------------------------------------------------------------
# 9. Terraform のインストール
# -------------------------------------------------------------
RUN curl https://apt.releases.hashicorp.com/gpg | gpg --dearmor > hashicorp.gpg \
    && install -o root -g root -m 644 hashicorp.gpg /usr/share/keyrings/ \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update \
    && apt-get install -y terraform

# -------------------------------------------------------------
# 10. zsh + Oh My Zsh インストール
# -------------------------------------------------------------
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && chsh -s /usr/bin/zsh

# -------------------------------------------------------------
# 11. Oh My Zsh プラグインの設定
#   プラグイン
#   - git
#   - aws
#   - history
#   - zsh-autosuggestions
#   - zsh-syntax-highlighting
# -------------------------------------------------------------
ENV ZSH=/root/.oh-my-zsh
ENV ZSH_CUSTOM=/root/.oh-my-zsh/custom

RUN git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions" \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" \
    # プラグイン: (git) → (git zsh-autosuggestions zsh-syntax-highlighting history)
    && sed -i 's/plugins=(git)/plugins=(git aws history zsh-autosuggestions zsh-syntax-highlighting)/' /root/.zshrc

# -------------------------------------------------------------
# 12. Zsh の履歴設定: 実行日時を記録 (EXTENDED_HISTORY) + 実行日時を表示 (HIST_STAMPS)
# -------------------------------------------------------------
RUN sed -i 's/# HIST_STAMPS="mm\/dd\/yyyy"/ \
    HIST_STAMPS="yyyy-mm-dd"\n \
    HISTSIZE=1000\n \
    SAVEHIST=2000/' \
    /root/.zshrc

# -------------------------------------------------------------
# 13. セッションログ取得用スクリプト (RAW → col -b → CLEAN)
# -------------------------------------------------------------
RUN echo '#!/bin/bash'                                                        >  /usr/local/bin/start-clean-session.sh \
    && echo 'LOGDIR="/var/log"'                                               >> /usr/local/bin/start-clean-session.sh \
    && echo 'mkdir -p "$LOGDIR"'                                              >> /usr/local/bin/start-clean-session.sh \
    && echo 'BASENAME="$(date +%Y%m%d)_session"'                              >> /usr/local/bin/start-clean-session.sh \
    && echo 'RAW_LOGFILE="$LOGDIR/${BASENAME}.raw"'                           >> /usr/local/bin/start-clean-session.sh \
    && echo 'CLEAN_LOGFILE="$LOGDIR/${BASENAME}.log"'                         >> /usr/local/bin/start-clean-session.sh \
    && echo ''                                                                >> /usr/local/bin/start-clean-session.sh \
    && echo 'echo "Starting script session. RAW => $RAW_LOGFILE"'             >> /usr/local/bin/start-clean-session.sh \
    && echo 'script -q -f -c "zsh" "$RAW_LOGFILE"'                            >> /usr/local/bin/start-clean-session.sh \
    && echo 'echo "Script ended. Converting to plain text => $CLEAN_LOGFILE"' >> /usr/local/bin/start-clean-session.sh \
    && echo 'col -b < "$RAW_LOGFILE" > "$CLEAN_LOGFILE"'                      >> /usr/local/bin/start-clean-session.sh \
    && echo 'echo "Done. Raw log: $RAW_LOGFILE"'                              >> /usr/local/bin/start-clean-session.sh \
    && echo 'echo "      Cleaned: $CLEAN_LOGFILE"'                            >> /usr/local/bin/start-clean-session.sh \
    && chmod +x /usr/local/bin/start-clean-session.sh

# -------------------------------------------------------------
# 14. alias
# -------------------------------------------------------------
RUN echo "alias os='cat /etc/lsb-release'" >> /root/.zshrc

# -------------------------------------------------------------
# 15. 起動設定
# -------------------------------------------------------------
# コンテナが起動したら script 経由で zsh に入る
ENTRYPOINT ["/usr/local/bin/start-clean-session.sh"]
