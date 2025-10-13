# MAKEFILE FILE: Makefile
#
# Purpose   : Controls iedit compilation and tests in a clean environment.
# Created   : Tue Nov 24 07:51:14 2020 +0100
# Author    : Pierre Rouleau <prouleau001@gmail.com>
# ----------------------------------------------------------------------------
# Dependencies
# ------------
#
# GNU Make, Unix-like shell, Emacs, ert.el

# ----------------------------------------------------------------------------
# Code
# ----

# Emacs invocation
EMACS_COMMAND   := emacs

EMACS		:= $(EMACS_COMMAND) -Q -batch

EVAL := $(EMACS) --eval

PKGDIR := .

# Additional emacs loadpath
LOADPATH	:= -L .

# Files to compile
EL			:= $(sort $(wildcard iedit*.el))

# Compiled files
ELC			:= $(EL:.el=.elc)


.PHONY: clean autoloads batch-compile install uninstall test

all: clean autoloads batch-compile

$(ELC): %.elc: %.el
	$(EMACS) $(LOADPATH) -f batch-byte-compile $<

# Compile needed files
compile: $(ELC)

# Compile all files at once
batch-compile:
	$(EMACS) $(LOADPATH) -f batch-byte-compile $(EL)

# Remove all generated files
clean:
	rm -f $(ELC)
	-rm iedit-ran-tests.tag


# Run iedit test code
# Use a zero-byte file to remember the tests succeeded.
# Delete that tag file to run successful tests again
test:	iedit-ran-tests.tag
	@echo "To run tests again, update test file or remove the file iedit-ran-tests.tag"

iedit-ran-tests.tag: iedit-tests.elc
	@printf "***** Running Integration tests\n"
	$(EMACS_COMMAND) --batch -L . -l ert -l iedit-tests.el -f ert-run-tests-batch-and-exit
	touch iedit-ran-tests.tag

# Make autoloads file
autoloads:
	$(EVAL) "(progn (setq generated-autoload-file (expand-file-name \"iedit-autoloads.el\" \"$(PKGDIR)\")) \
(setq backup-inhibited t) (update-directory-autoloads \"$(PKGDIR)\"))"

PREFIX=/usr/local/share/
DESTDIR=${PREFIX}emacs/site-lisp/iedit/
install:
	test -d ${DESTDIR} || mkdir ${DESTDIR}
	cp -vf *.el $(DESTDIR)
	cp -vf *.elc $(DESTDIR)
	cp -vf iedit-autoloads.el $(DESTDIR)

uninstall:
	rm -vf ${DESTDIR}*.elc
	rm -vf ${DESTDIR}*.el

# ----------------------------------------------------------------------------
