ZSH=$HOME/.oh-my-zsh

autoload -U +X compinit && compinit
autoload -U +X bashcompinit && bashcompinit

plugins=(zsh-autosuggestions kubectl kubectx git-prompt)

export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export EDITOR='code --wait'
export VISUAL='code --wait'
export TERM=xterm-256color
export XDG_CONFIG_HOME=$HOME/.config
export ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=("${(@)ZSH_AUTOSUGGEST_ACCEPT_WIDGETS:#forward-char}")
export PATH="/home/app/hetzner-k3s/bin:$HOME/.krew/bin:./bin:$HOME/bin:$GOPATH/bin:$PATH"
export HISTFILE="/home/app/hetzner-k3s/.zsh_history"

source $ZSH/oh-my-zsh.sh
source <(kubectl completion zsh)
source <(stern --completion=zsh)

alias k="kubectl"
alias stern="stern -s 1s"

bindkey '^a' autosuggest-accept
bindkey '\C-[OC'	forward-word		# ctrl-right
bindkey "\e[1;5C"	forward-word		# ctrl-right

ulimit -n 65536

setTerminalText () {
  local mode=$1 ; shift
  echo -ne "\033]$mode;$@\007"
}

stt_title () {
  setTerminalText 2 $@;
}

k8s_prompt_info() {
  local ctx=$(kubectl config current-context 2>/dev/null)
  local ns=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)

  if [[ -n $ctx ]]; then
    echo "[%{$fg_bold[green]%}$ctx%{$reset_color%}:%{$fg_bold[blue]%}$ns%{$reset_color%}]"
  fi
}

PROMPT='[${${PROJECT##*/}%}] %~%b $(git_super_status) $(k8s_prompt_info)%\> '
RPROMPT='%T'

set -a
source /home/app/hetzner-k3s/.env.vars
set +a

echo "*" > /home/app/hetzner-k3s/tmp/.gitignore
echo "!.gitignore" >> /home/app/hetzner-k3s/tmp/.gitignore

eval `ssh-agent`
