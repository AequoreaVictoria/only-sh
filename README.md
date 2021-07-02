# only-sh
> A command whitelisting shell for Unix-like systems

This is a login shell that will only execute a single authorized command. It
obtains the name of the authorized command from its own filename, allowing easy
reuse by symlinking the binary to a new location. The use of this shell allows
policy to be enforced regardless of how the user is being accessed.

Proper C errno codes are returned for almost every condition the shell
encounters, though once it successully executes the authorized command the
return code will instead come from that program. There are no other features.

It is written in [Zig][0] with no external dependencies.


## Building & Installing

        zig build -Drelease-small
        sudo install -D -m755 ./zig-out/bin/only-sh /bin


## Usage
Create restricted shells by making symbolic links to `only-sh`. For example:

        sudo ln -s /bin/only-sh /bin/rsync-only
        sudo ln -s /bin/only-sh /bin/mysql-only

These link names must maintain the `<program>-only` form, as above. The
`<program>` portion must be at least one character. The shell will return
`wrong filename` if this is not properly followed.

Update the `/etc/shells` list to add the new restricted shells.

You may now update `/etc/passwd` and assign a restricted shell to a user.

They will not be able to execute another command than `<program>` from within
the shell.


## Uninstalling
Remove your restricted shell links and then `sudo rm /bin/only-sh`.

Remember to update `/etc/shells` and `/etc/passwd`.


## License
[0BSD][1]

[0]: https://ziglang.org/
[1]: https://opensource.org/licenses/0BSD
