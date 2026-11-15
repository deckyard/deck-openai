#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
#
# openai overrides the shared example runner.
#
# The examples talk to a model server: OpenAI with an API key, or a local
# one such as Ollama. CI has neither, so it checks that each example still
# parses against the current language and module surface; `jennifer lint`
# covers them too, in the test workflow, and reaches undefined calls. The
# suite tests every call against a loopback fake replaying recorded replies.
set -euo pipefail
cd "$(dirname "$0")/.."
exec env EXAMPLES_SKIP_RUN=1 tools/check-examples-shared.sh
