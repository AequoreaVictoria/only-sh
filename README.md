# only-sh
> A command whitelisting shell

This is a login shell that will only execute a single whitelisted command. It
obtains the name of the whitelisted command from its own filename, allowing
easy reuse by simply linking the file to a new location. This allows policy to
be enforced regardless of how the user is attempting to login, rather than
relying on daemon-specific (i.e. OpenSSH) features for policy enforcement.

The shell has basic quotation support, only allowing you to pass a string with
spaces as a single argument. You may use either single or double quotes. When
outside of quotation strings of spaces will be treated as a single space. There
are no other features.

It is written in [Zig][0]. On Linux it is statically linked with [musl][2] libc.
It has no external dependencies beyond libc.


### Building & Installing
You must have the [Zig][0] programming toolchain installed. Execute:

        zig build -Drelease-small=true
        sudo install -D -m755 ./out/only-sh /bin


### Usage
Create restricted shells by making symbolic links to `only-sh`. For example:

        sudo ln -s /bin/only-sh /bin/rsync-only
        sudo ln -s /bin/only-sh /bin/mysql-only

These link names must maintain the `<program>-only` form, as above.

Update the `/etc/shells` list to add the new restricted shells.

You may now update `/etc/passwd` and assign a restricted shell to a user.

They will not be able to execute another command than `<program>` from within
the shell.


### Uninstalling
Remove your restricted shell links and then `sudo rm /bin/only-sh`.

Remember to update `/etc/shells` and `/etc/passwd`.


### License
[0BSD][1]


[0]: https://ziglang.org/
[1]: https://opensource.org/licenses/0BSD
[2]: https://musl.libc.org/
