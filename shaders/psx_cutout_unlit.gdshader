shader_type spatial;
// See-through and unlit: the thing on the fifth floor.
render_mode unshaded, cull_disabled;

#define PSX_CUTOUT
#include "res://addons/psx_look/shaders/psx.gdshaderinc"
