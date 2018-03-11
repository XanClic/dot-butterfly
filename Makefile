OUT_DIR = build
STRUCTS_IN = $(wildcard src/structs/*.struct.pc)
STRUCTS_OUT = $(patsubst src/structs/%.struct.pc,$(OUT_DIR)/structs/%.struct,$(STRUCTS_IN))

MKDIR = mkdir -p
CP = cp
RM = rm

.PHONY: all

all: $(OUT_DIR)/config.json
	@echo "===== target 'all' reached ====="
	@echo
	@echo "All done, feel free to do:"
	@echo "$$ ln -s '$(PWD)/$(OUT_DIR)' ~/.butterfly"

$(OUT_DIR):
	$(MKDIR) "$@"

$(OUT_DIR)/structs:
	$(MKDIR) "$@"

$(OUT_DIR)/config.json: src/config.json $(OUT_DIR) $(STRUCTS_OUT)
	$(CP) "$<" "$@"

$(OUT_DIR)/structs/%.struct: src/structs/%.struct.pc $(OUT_DIR)/structs
	./pc-to-sbc-asm.rb pc.bnf < "$<" | ./sbc-asm-to-sbc-bin.rb > "$@"

clean:
	$(RM) -rf "$(OUT_DIR)/*"
