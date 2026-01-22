# Convert SystemVerilog (.sv) files to Verilog (.v) using sv2v

SV_FILES := $(shell find src/ -follow -name "*.sv" -type f 2>/dev/null | grep -v '/src/src')
SVH_FILES := $(shell find src/ -follow -name "*.svh" -type f 2>/dev/null | grep -v '/src/src')
INCLUDE_FLAGS := $(foreach dir,$(sort $(dir $(SVH_FILES))),-I $(dir))
V_FILES := $(SV_FILES:.sv=.sv2v.v)

.PHONY: sv2v clean test

sv2v:
	@mkdir -p .sv2v_temp
	@sv2v $(INCLUDE_FLAGS) $(SV_FILES) -w .sv2v_temp
	@for svfile in $(SV_FILES); do \
		module_name=$$(basename "$$svfile" .sv); \
		if [ -f ".sv2v_temp/$$module_name.v" ]; then \
			mv ".sv2v_temp/$$module_name.v" "$$(dirname "$$svfile")/$$module_name.sv2v.v"; \
		fi; \
	done
	@rm -rf .sv2v_temp

clean:
	@rm -f $(V_FILES)

test:
	$(MAKE) -C test test_all
