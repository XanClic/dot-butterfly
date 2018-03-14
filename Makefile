OUT_DIR = build
TMP_DIR = tmp
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

$(TMP_DIR)/structs:
	$(MKDIR) "$@"

$(OUT_DIR)/config.json: src/config.json $(OUT_DIR) $(STRUCTS_OUT)
	$(CP) "$<" "$@"

$(TMP_DIR)/structs/%.struct.asm: src/structs/%.struct.pc $(TMP_DIR)/structs
	./pc-to-sbc-asm.rb pc.bnf < "$<" > "$@"

$(OUT_DIR)/structs/%.struct: $(TMP_DIR)/structs/%.struct.asm $(OUT_DIR)/structs
	./sbc-asm-to-sbc-bin.rb < "$<" > "$@"

clean:
	$(RM) -rf "$(OUT_DIR)/*"
