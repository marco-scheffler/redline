#include <metal_stdlib>
using namespace metal;

// Heavy floating-point kernel used to saturate the GPU.
kernel void stress(device float *data [[buffer(0)]],
                   uint id [[thread_position_in_grid]]) {
    float x = data[id];
    for (int i = 0; i < 5000; i++) {
        x = sin(x) * cos(x) + sqrt(abs(x) + 1.0);
        x = x * x - floor(x) + fract(x * 3.14159);
        x = log2(abs(x) + 1.0) * exp2(fract(x));
    }
    data[id] = x;
}
