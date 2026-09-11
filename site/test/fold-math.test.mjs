// Mirrors native/Tests/FoldCoreTests so the web demo and the Mac app share one geometry.
// Run: node --test site/test/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sourceUV, progress, smooth, clamp, defaults } from '../dist/fold-math.mjs';

test('working plane is identity across the screen', () => {
  for (const angle of [75, 90, 105, 135])
    for (const u of [0, .2, .5, .9, 1])
      for (const v of [0, .3, .7, 1]) {
        const uv = sourceUV(u, v, angle, angle, 1.6);
        assert.ok(uv, `null at ${angle} ${u} ${v}`);
        assert.ok(Math.abs(uv[0] - u) < 1e-10 && Math.abs(uv[1] - v) < 1e-10, `drift at ${angle} ${u} ${v}: ${uv}`);
      }
});

test('hinge is stationary', () => {
  for (const angle of [18, 30, 60, 90, 105]) {
    const uv = sourceUV(.5, 1, angle, 105, 1.6);
    assert.ok(uv);
    assert.ok(Math.abs(uv[0] - .5) < 1e-10 && Math.abs(uv[1] - 1) < 1e-10);
  }
});

test('bad input cannot produce NaN', () => {
  assert.equal(sourceUV(NaN, 0, 90, 105, 1.6), null);
  assert.equal(sourceUV(.5, .5, 90, 105, 0), null);
  assert.equal(progress(NaN), 0);
  assert.equal(clamp(Infinity, 0, 1, .5), .5);
});

test('smoothing is independent of frame rate', () => {
  let slow = 105, fast = 105;
  for (let i = 0; i < 30; i++) slow = smooth(slow, 30, 1 / 30, .5);
  for (let i = 0; i < 120; i++) fast = smooth(fast, 30, 1 / 120, .5);
  assert.ok(Math.abs(slow - fast) < 1e-9);
});

test('progress runs 0 → 1 from working angle to fade angle', () => {
  assert.equal(progress(defaults.workingAngle), 0);
  assert.equal(progress(defaults.fadeAngle), 1);
  assert.equal(progress(200), 0);
  assert.equal(progress(-10), 1);
});

test('top of the panel projects to a sensible region while closing', () => {
  // As the lid tilts toward the viewer, the top edge should read from lower on the
  // reference plane (the picture appears to stay put while the glass moves over it).
  const uv = sourceUV(.5, 0, 80, 105, 1.6);
  assert.ok(uv && uv[1] > 0 && uv[1] < 1, `top edge left the picture: ${uv}`);
});
