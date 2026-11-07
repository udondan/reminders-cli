#!/bin/zsh
# Types `reminders show <prefix>` and TAB into an interactive zsh with the generated completion
# (fpath/_reminders in the current directory), then runs the completed line through a function
# that prints the list name argument, i.e. exactly what zsh would pass to the command.
emulate -L zsh
zmodload zsh/zpty

prefix=$1
out=$PWD/zsh-completed.txt
rm -f $out

# Keep reading the pty for $1 tenths of a second, so zsh never blocks on its output.
pump() {
    local i
    for i in {1..$1}; do
        while zpty -r -t z _chunk; do :; done
        sleep 0.1
    done
}

zpty z 'zsh -f -i'
zpty -w z "PS1='%% '; fpath=($PWD/fpath \$fpath); autoload -Uz compinit; compinit -u -D"
zpty -w z "record() { print -rn -- \"\$3\" > ${(q)out}; }"
pump 20
zpty -w -n z "reminders show $prefix"$'\t'
pump 50
# Ctrl-A, prepend `record `, Enter.
zpty -w -n z $'\x01record \n'
for i in {1..100}; do
    [[ -e $out ]] && break
    pump 1
done
zpty -d z
[[ -e $out ]] && print -r -- "$(<$out)"
