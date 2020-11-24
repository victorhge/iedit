# makefile for iedit.


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


.PHONY: clean autoloads batch-compile install uninstall

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
