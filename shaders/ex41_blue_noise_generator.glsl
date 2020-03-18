//
// Blue Noise Generator
//   python -m src.app --width 256 --height 256 shaders/ex41_blue_noise_generator.glsl --offscreen shaders/images/ex41_blue_noise_generator.png
//
// - References
//   - Blue Noise Generator of by paniq https://www.shadertoy.com/view/XtdyW2
//   - G EORGIEV I., F AJARDO M.: Blue-noise dithered sampling.
//
// - TODO
//   - Proper throttling mechanism so not to crush when offscreen (maybe by config option?)
//   - Higher dimention 2, 3, 4
//

/*
%%config-start%%
samplers:
  - name: fb
    type: framebuffer
    size: [256, 256]
    mipmap: false
    wrap: repeat
    filter: nearest

programs:
  - name: mainImage2
    output: fb
    samplers:
      - fb
  - name: mainImage1
    output: $default
    samplers:
      - fb

offscreen_option:
  fps: 60
  num_frames: 180
  # num_frames: 600
%%config-end%%
*/


// Constants
#include "utils/hash_v0.glsl"
#include "common_v0.glsl"

//
// Configuration
//

// - global seed
const int kSeed = 0;

// - [0, 1]-uniform buffer initialization strategy
const int kInitType = 0; // 0: y-gradient, 1: frag coord hash

// - Neighbors to include for objective function evaluation
const int kRadius = 8;
// const int kRadius = 12;

// - Fraction of permutation pairs to kull.
//   (the lower this value is, the faster the evolution. but might not converge.)
const float kKullFraction = 0.5;
// const float kKullFraction = 0.8;

// - Parameter of `objective_g` from the paper "Blue-noise dithered sampling"
const float kSigmaI = 2.1;
const float kSigmaS = 1.0;

// - Ad-hoc parameter (it depends on all other constants)
const float kAdhocTemperature = 0.001;
// const float kAdhocTemperature = 0.01;
// const float kAdhocTemperature = 0.05;

// - See "samplers: - ... size: [256, 256]" in above config
const int kFbSize = 256;
const int kFbSizePow2 = 8;

//
// Utilities
//

float reduceMax(vec2 v) {
  return max(v[0], v[1]);
}

float reduceSum(vec3 v) {
  return v[0] + v[1] + v[2];
}

ivec2 wrapRepeat(ivec2 p) {
  return p % ivec2(kFbSize);
}


//
// Display
//
void mainImage1(out vec4 frag_color, in vec2 frag_coord, sampler2D fb){

  ivec2 frag_icoord = ivec2(floor(frag_coord));
  ivec2 texcoord = frag_icoord;

  {
    // Mouse zoom interaction
    // TODO: it seems half pixel off at box's boundary
    const float kZoomFactor = 16.0;
    const vec2 kZoomBoxSize = vec2(10.0, 10.0) * kZoomFactor;
    bool activated, down;
    vec2 last_click_pos, last_down_pos;
    getMouseState(iMouse, /*out*/ activated, down, last_click_pos, last_down_pos);

    if (down) {
      vec2 mouse_icoord = floor(last_down_pos);
      bool frag_inside = reduceMax(abs(frag_icoord - mouse_icoord) - kZoomBoxSize / 2.0) <= 0.0;
      if (frag_inside) {
        texcoord = ivec2(mouse_icoord + (frag_icoord - mouse_icoord) / kZoomFactor);
      }
    }
  }

  float v = texelFetch(fb, texcoord, 0)[0];
  frag_color = vec4(vec3(v), 1.0);
}


//
// Optimization code
//

float objective_g(ivec2 dp, float df) {
  float c_dp = length(dp) * length(dp);
  float c_df = length(df);
  return exp(- c_dp / kSigmaI - c_df / kSigmaS);
}

void estimateObjective(ivec2 p0, ivec2 p1, sampler2D fb, out float obj_curr, out float obj_perm) {
  obj_curr = 0.0;
  obj_perm = 0.0;
  float f_p0 = texelFetch(fb, p0, 0)[0];
  float f_p1 = texelFetch(fb, p1, 0)[0];

  for (int dx = -kRadius; dx <= kRadius; dx++) {
    for (int dy = -kRadius; dy <= kRadius; dy++) {
      if (dx == 0 && dy == 0) { continue; }

      ivec2 dp = ivec2(dx, dy);
      float l = length(dp);
      if (kRadius < l) { continue; }

      ivec2 p0_dp = wrapRepeat(p0 + dp);
      ivec2 p1_dp = wrapRepeat(p1 + dp);
      float f_p0_dp = texelFetch(fb, p0_dp, 0)[0];
      float f_p1_dp = texelFetch(fb, p1_dp, 0)[0];

      obj_curr += objective_g(dp, f_p0 - f_p0_dp);
      obj_curr += objective_g(dp, f_p1 - f_p1_dp);

      obj_perm += objective_g(dp, f_p0 - f_p1_dp);
      obj_perm += objective_g(dp, f_p1 - f_p0_dp);
    }
  }
}


void mainImage2(out vec4 frag_color, vec2 frag_coord, sampler2D fb) {
  //
  // Initialize buffer by [0, 1]-uniform data
  // (it should be uniform for {0, 1, .., 255} / 255)
  //
  if (iFrame <= 1) {
    // Gradient along y
    // (it has to be iResolution[1] % 256 == 0, to achieve complete uniformity from this.)
    if (kInitType == 0) {
      float v = floor(frag_coord[1]) / float(kFbSize - 1);
      frag_color[0] = v;
      return;
    }

    // Hash by coordinate (it won't be "complete" uniform value, but okay)
    if (kInitType == 1) {
      frag_color[0] = hash21(frag_coord + kSeed);
      return;
    }
  }

  //
  // Optimization
  //

  uint step_id = uint(iFrame + kSeed);
  uvec2 step_hash = hash12u(step_id);

  //
  // Choose swap candidate pair by involutive permutation (p |-> p ^ hash)
  //
  // NOTE:
  //  - When p's domain is not perfectly p bits (i.e. {0, .., 2^p - 1}),
  //    this simple xor doesn't become involution.
  //  - From spatially perspective, what xor permutation does is
  //    swapping two pixel coordinates with differeing bits where hash is on.
  //
  ivec2 perm_hash = ivec2(step_hash >> (32u - uint(kFbSizePow2))); // // in {0, .., 2^p - 1}
  ivec2 p0 = ivec2(floor(frag_coord));
  ivec2 p1 = p0 ^ perm_hash;

  // Make pair's id based on total order and concatenating bits
  uvec2 pair_id = uvec2(min(p0, p1) | (max(p0, p1) << kFbSizePow2));
  float pair_hash0 = uintToUnitFloat(hash21u(pair_id));
  float pair_hash1 = uintToUnitFloat(hash21u(pair_id + step_id));


  //
  // Stochastically execute swap
  //

  // For `estimateObjective` below to be valid, we shouldn't swap everything at single step.
  // So, we first kulls swap-candidate pairs randomly.
  if (pair_hash0 <= kKullFraction) {  // Bernoulli trial
    frag_color[0] = texelFetch(fb, p0, 0)[0];
    return;
  }

  // Estimate objective function for current/permuation configuration
  float obj_curr, obj_perm;
  estimateObjective(p0, p1, fb, /*out*/ obj_curr, obj_perm);

  // "Simulated annealing"-like routine WITHOUT cooling
  float obj_diff = obj_perm - obj_curr;
  float temperature = kAdhocTemperature;
  float probability = exp((obj_curr - obj_perm) / temperature);
  bool swap = pair_hash1 < probability;  // Bernoulli trial

  ivec2 p = swap ? p1 : p0;
  frag_color[0] = texelFetch(fb, p, 0)[0];
}
