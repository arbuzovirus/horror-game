shader_type spatial;
// PSX Look material with see-through pixels, drawn from both sides (railings, decals, paper).
render_mode vertex_lighting, specular_disabled, cull_disabled;

#define PSX_CUTOUT
#include "res://addons/psx_look/shaders/psx.gdshaderinc"
