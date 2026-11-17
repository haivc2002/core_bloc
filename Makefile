# ==============================================================================
# LAMSU APP - MAKEFILE HELPER
# ==============================================================================

# Danh sách các target nhận tham số (vd: make module register, make entity <path>)
TARGETS_WITH_ARG := module gen m entity e state s

ifneq ($(filter $(firstword $(MAKECMDGOALS)),$(TARGETS_WITH_ARG)),)
  ARG := $(word 2,$(MAKECMDGOALS))
  ARG2 := $(word 3,$(MAKECMDGOALS))
  ifneq ($(ARG),)
    # Định nghĩa dummy target và .PHONY để make không báo lỗi "No rule to make target" hoặc "is up to date"
    .PHONY: $(ARG)
    $(eval $(ARG):;@:)
  endif
  ifneq ($(ARG2),)
    .PHONY: $(ARG2)
    $(eval $(ARG2):;@:)
  endif
endif

.PHONY: help module gen m entity e state s build watch clean get layout

# Default target khi chỉ gõ 'make'
help:
	@echo "=============================================================="
	@echo "🚀 LAMSU APP - CLI SHORTCUTS"
	@echo "=============================================================="
	@echo "  make module <tên>   Tạo module mới (Clean Architecture)"
	@echo "                      Alias ngắn: make m <tên> hoặc make gen <tên>"
	@echo "                      Ví dụ: make module register"
	@echo ""
	@echo "  make entity <tên>   Sinh Entity & toEntity() từ Model"
	@echo "                      Alias ngắn: make e <tên>"
	@echo "                      Ví dụ: make entity user (hoặc make e user)"
	@echo "                      Hỗ trợ: make entity setting, make entity setting/user, hoặc full path"
	@echo ""
	@echo "  make state <tên>    Build Freezed siêu tốc cho riêng module (không quét cả project)"
	@echo "                      Alias ngắn: make s <tên>"
	@echo "                      Ví dụ: make state setting (hoặc make s setting)"
	@echo ""
	@echo "  make build          Chạy build_runner build 1 lần"
	@echo "  make watch          Chạy build_runner watch (tự sinh code khi save)"
	@echo "  make layout         Sinh LayoutRegistry và FeatureAccess"
	@echo "  make get            Chạy flutter pub get"
	@echo "  make clean          Dọn dẹp build cache & lấy lại package"
	@echo "=============================================================="

# Tạo module (Hỗ trợ: make module <name>, make gen <name>, make m <name>)
module gen m:
	@if [ -z "$(ARG)" ]; then \
		echo "❌ Lỗi: Bạn chưa truyền tên module!"; \
		echo "👉 Cách dùng: make module <ten_module>"; \
		echo "👉 Ví dụ:     make module register"; \
		exit 1; \
	fi
	@echo "⚡ Đang tạo module: $(ARG)..."
	@dart run core_bloc/lib/generator/generate_module.dart $(ARG)

# Sinh Entity từ Model (Hỗ trợ: make entity user, make e user, make entity setting, make entity <path>)
entity e:
	@if [ -z "$(ARG)" ]; then \
		echo "❌ Lỗi: Bạn chưa truyền tên model hoặc module!"; \
		echo "👉 Cách dùng: make entity <tên_model hoặc module>"; \
		echo "👉 Ví dụ:     make entity user"; \
		echo "👉 Hoặc ngắn: make e user"; \
		echo "👉 Hoặc:      make entity setting"; \
		echo "👉 Đầy đủ:    make entity lib/feature/setting/data/model/model_user.dart"; \
		exit 1; \
	fi
	@TARGET="$(ARG)"; \
	if [ -n "$(ARG2)" ]; then \
		TARGET="$(ARG)/$(ARG2)"; \
	fi; \
	dart run core_bloc/lib/generator/generate_entity.dart "$$TARGET"

# Build Freezed siêu tốc cho riêng module (không quét cả project)
# Hỗ trợ: make state <module>, make s <module>, make state <path>
state s:
	@if [ -z "$(ARG)" ]; then \
		echo "❌ Lỗi: Bạn chưa truyền tên module hoặc file state!"; \
		echo "👉 Cách dùng: make state <tên_module>"; \
		echo "👉 Ví dụ:     make state setting"; \
		echo "👉 Hoặc ngắn: make s setting"; \
		exit 1; \
	fi
	@TARGET="$(ARG)"; \
	if echo "$$TARGET" | grep -q "lib/feature/"; then \
		if [ -f "$$TARGET" ]; then \
			DIR=$$(dirname "$$TARGET"); \
			FILTER="$$DIR/**"; \
		else \
			FILTER="$$TARGET/**"; \
		fi; \
	else \
		MODULE=$$(echo "$$TARGET" | tr '[:upper:]' '[:lower:]'); \
		FILTER="lib/feature/$$MODULE/presentation/**"; \
	fi; \
	echo "⚡ Đang build Freezed siêu tốc cho: $$FILTER..."; \
	dart run build_runner build -d --build-filter="$$FILTER"

# Chạy build_runner build (1 lần)
build:
	@echo "🔨 Đang chạy build_runner build..."
	@dart run build_runner build

# Chạy build_runner watch (lắng nghe file thay đổi)
watch:
	@echo "👀 Đang chạy build_runner watch..."
	@dart run build_runner watch

# Lấy dependencies
get:
	@echo "📦 Đang tải packages..."
	@flutter pub get

# Dọn dẹp cache
clean:
	@echo "🧹 Đang dọn dẹp cache..."
	@flutter clean
	@flutter pub get

# Lệnh build siêu tốc chỉ dành cho Layout Registry
layout:
	dart run build_runner build --build-filter="lib/router/layout_registry.g.dart" --build-filter="lib/shared/feature_access*.g.dart"
