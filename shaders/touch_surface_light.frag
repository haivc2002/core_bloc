#include <flutter/runtime_effect.glsl>

uniform vec2 uCenter;
uniform float uRadius;
uniform float uGlow;
uniform float uRelease;
uniform float uStrength;
uniform vec2 uSize;
uniform vec4 uCorners;
uniform float uRimStrength;

out vec4 fragColor;

float panelDistance(vec2 position) {
  vec2 halfSize = uSize * 0.5;
  vec2 p = position - halfSize;
  vec2 side = p.x < 0.0 ? uCorners.xz : uCorners.yw;
  float corner = min(p.y < 0.0 ? side.x : side.y, min(halfSize.x, halfSize.y));
  vec2 q = abs(p) - halfSize + corner;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
}

// Project onto the perimeter from the center. Adjoining sides share the
// same coordinate at a corner, so the light can pass through continuously.
float perimeterPosition(vec2 position) {
  vec2 halfSize = uSize * 0.5;
  vec2 p = (position - halfSize) / halfSize;
  float extent = max(abs(p.x), abs(p.y));
  vec2 edge = halfSize * (1.0 + p / max(extent, 0.0001));

  if (abs(p.x) > abs(p.y)) {
    return p.x > 0.0 ? uSize.x + edge.y : 2.0 * uSize.x + 2.0 * uSize.y - edge.y;
  }
  return p.y < 0.0 ? edge.x : 2.0 * uSize.x + uSize.y - edge.x;
}

void main() {
  vec2 position = FlutterFragCoord().xy;
  float contactDistance = length(position - uCenter);
  float r = contactDistance / uRadius;
  float halo = exp2(-3.3 * r * r) * uGlow;

  float crest = 0.08 + 1.85 * uRelease;
  float width = 0.54 + 0.48 * uRelease;
  float waveDistance = (r - crest) / width;
  float envelope = smoothstep(0.0, 0.10, uRelease)
      * (1.0 - smoothstep(0.28, 1.0, uRelease));
  float wave = exp2(-1.65 * waveDistance * waveDistance) * envelope;

  float alpha = clamp(uStrength * (halo + 0.68 * wave), 0.0, 1.0);
  // Outside contacts still project onto the rim until the pointer is released.
  float contactDepth = max(0.0, -panelDistance(uCenter));
  float contactNearEdge = 1.0 - smoothstep(18.0, 52.0, contactDepth);
  if (contactNearEdge > 0.0 && uGlow > 0.0) {
    float depth = max(0.0, -panelDistance(position));
    // Fill the rim uniformly, with only a subpixel transition at its inner edge.
    float rim = 1.0 - smoothstep(1.25, 1.75, depth);
    if (rim > 0.0) {
      float distance = abs(perimeterPosition(position) - perimeterPosition(uCenter));
      float perimeter = 2.0 * (uSize.x + uSize.y);
      float alongEdge = 1.0 - smoothstep(60.0, 160.0, min(distance, perimeter - distance));
      alpha = mix(alpha, 1.0, rim * alongEdge * contactNearEdge * uGlow * uRimStrength);
    }
  }
  fragColor = vec4(vec3(alpha), alpha);
}
