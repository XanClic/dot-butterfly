.butterfly
==========

How to use
----------

This repository contains the sources for `~/.butterfly` (related: my “butterfly”
repository).  To make use of them, simply clone the repo, execute `make` in its
root directory, and link the resulting `build` to `~/.butterfly`.

What there is
-------------

Besides an initial configuration file, this repository mainly contains sources
for structure definitions.  Since butterfly uses a stupidly overly complicated
byte code interpreter to extract structured data, there has to be some source
code for that, and it is here.

Since writing that code in pure assembly would be rather cumbersome, it is
written in some more abstract language (called PC, and I have already forgotten
what that was supposed to mean), so this repository contains the sources in that
language, a compiler from PC to byte code assembly, and an assembler.
