// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

export function requireReviewedNode() {
  if (process.version !== "v24.19.0") {
    throw new Error(`benchmark contract validation requires Node v24.19.0; found ${process.version}`);
  }
}
