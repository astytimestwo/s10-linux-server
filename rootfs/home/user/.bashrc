# S10 ~/.bashrc
# Node tools from "npm install -g" live on the big disk (/srv/npm-global, no root needed).
# Set before the interactive check below, so scripts and agents get it too.
case ":$PATH:" in *:/srv/npm-global/bin:*) ;; *) PATH="/srv/npm-global/bin:$PATH" ;; esac
export PATH
[ -f /etc/bash/bashrc ] && . /etc/bash/bashrc
[ -r /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
case $- in *i*) ;; *) return ;; esac

HISTSIZE=10000
HISTFILESIZE=50000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize

PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '

alias t='tmux new -A -s main'      # start or re-attach the main tmux session
alias ll='ls -lah --color=auto'
alias ls='ls --color=auto'
alias temps='tail -n 20 /var/log/s10-temps.csv | column -s, -t'
alias st='s10-status'
export EDITOR=nano

# On SSH login (outside tmux): one-line health summary + hint
if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then
	s10-status 2>/dev/null
	echo "Type 't' for tmux, 'claude' for Claude Code, 'temps' for the temperature log."
fi
