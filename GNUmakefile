# Override REBAR to use an installed rebar3 or a shared workspace copy.
REBAR ?= ./rebar3
REBAR_URL ?= https://s3.amazonaws.com/rebar3/rebar3
REBAR_OPTS ?=

.PHONY: all compile upgrade-deps shell test xref dialyzer doc edoc clean dist-clean

all: compile

$(REBAR):
	curl --fail --location --proto '=https' --proto-redir '=https' $(REBAR_URL) -o $(REBAR).tmp
	chmod +x $(REBAR).tmp
	mv $(REBAR).tmp $(REBAR)

compile: $(REBAR)
	$(REBAR) $(REBAR_OPTS) compile

upgrade-deps: $(REBAR)
	$(REBAR) $(REBAR_OPTS) upgrade

shell: compile
	$(REBAR) $(REBAR_OPTS) shell

# Includes the vendored W3C fixtures; no external fixture download is needed.
test: $(REBAR)
	$(REBAR) $(REBAR_OPTS) eunit

xref: $(REBAR)
	$(REBAR) $(REBAR_OPTS) as test xref

dialyzer: $(REBAR)
	$(REBAR) $(REBAR_OPTS) dialyzer

doc: $(REBAR)
	$(REBAR) $(REBAR_OPTS) ex_doc

edoc: $(REBAR)
	$(REBAR) $(REBAR_OPTS) edoc

clean: $(REBAR)
	$(REBAR) $(REBAR_OPTS) clean

dist-clean: clean
	$(REBAR) $(REBAR_OPTS) clean -a
	rm -f ./rebar3 ./rebar3.tmp
