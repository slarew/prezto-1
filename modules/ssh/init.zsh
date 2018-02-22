#
# Provides for an easier use of SSH by setting up ssh-agent.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Return if requirements are not found.
if (( ! $+commands[ssh-agent] )); then
  return 1
fi

# Set the path to the SSH directory.
_ssh_dir="$HOME/.ssh"

# Set the path to the environment file if not set by another module.
_ssh_agent_env="${_ssh_agent_env:-${TMPDIR:-/tmp}/ssh-agent.env.$UID}"

# Due to the predictability of the env file, check the env file exists and is
# owned by current EUID before trusting it.
if [[ -f "$_ssh_agent_env" && ! -O "$_ssh_agent_env" ]]; then
  cat 1>&2 <<-EOF
	ERROR: Cannot trust the SSH agent environment variables persistence
	file because it is owned by another user.
	The ssh-agent will not be started.
	$_ssh_agent_env
	EOF
  unset _ssh_{dir,agent_env}
  return 1
fi

# If a socket exists at SSH_AUTH_SOCK, assume ssh-agent is already running and
# skip starting it.
if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
  # Try to grab previously exported environment variables.
  source "$_ssh_agent_env" 2> /dev/null

  # Do not start ssh-agent if the socket and PID from the last start of
  # ssh-agent are still good.
  if [[ ! -S "$SSH_AUTH_SOCK" || ! -O "$SSH_AUTH_SOCK" ]]; then
    # NB: `ps` and the like are not entirely reliable for finding the running
    # ssh-agent.  For example, if procfs on Linux is mounted with hidepid > 0,
    # then ps and pgrep appear to fail to find a running ssh-agent under the
    # current user.  Sending SIGCONT (continue) should be benign and should
    # only succeed if the current user is able to signal  the pid (either USER
    # owns SSH_AGENT_PID process or USER is root).  It's possible ssh-agent
    # with pid SSH_AGENT_PID died and left SSH_AUTH_SOCK behind and a new
    # process receives SSH_AGENT_PID and would successfully receive SIGCONT, in
    # which case we'll just let the user resolve this issue manually since it
    # should be rare and rather unlikely.
    if ! kill -CONT "${SSH_AGENT_PID:-BADPID}" 2> /dev/null ; then
      eval "$(ssh-agent | sed '/^echo /d' | tee "$_ssh_agent_env")"
    fi
  fi
fi

# Load identities.
if ssh-add -l 2>&1 | grep -q 'The agent has no identities'; then
  zstyle -a ':prezto:module:ssh:load' identities '_ssh_identities'
  # ssh-add has strange requirements for running SSH_ASKPASS, so we duplicate
  # them here. Essentially, if the other requirements are met, we redirect stdin
  # from /dev/null in order to meet the final requirement.
  #
  # From ssh-add(1):
  # If ssh-add needs a passphrase, it will read the passphrase from the current
  # terminal if it was run from a terminal. If ssh-add does not have a terminal
  # associated with it but DISPLAY and SSH_ASKPASS are set, it will execute the
  # program specified by SSH_ASKPASS and open an X11 window to read the
  # passphrase.
  if [[ -n "$DISPLAY" && -x "$SSH_ASKPASS" ]]; then
    ssh-add "${_ssh_identities:+$_ssh_dir/${^_ssh_identities[@]}}" < /dev/null 2> /dev/null
  else
    ssh-add ${_ssh_identities:+$_ssh_dir/${^_ssh_identities[@]}} 2> /dev/null
  fi

  if [[ "$OSTYPE" == darwin* ]]; then
    # macOS: `ssh-add -A` will load all identities defined in Keychain.
    # Assume `/usr/bin/ssh-add` is Apple customized version that understands
    # the `-A` switch.
    /usr/bin/ssh-add -A
  fi
fi

# Clean up.
unset _ssh_{dir,identities,agent_env}
