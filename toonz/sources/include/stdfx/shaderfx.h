#pragma once

#ifndef SHADERFX_H
#define SHADERFX_H

#include "tcommon.h"

#undef DVAPI
#undef DVVAR
#ifdef TNZSTDFX_EXPORTS
#define DVAPI DV_EXPORT_API
#define DVVAR DV_EXPORT_VAR
#else
#define DVAPI DV_IMPORT_API
#define DVVAR DV_IMPORT_VAR
#endif

//=========================================================

//    Forward declarations

class TFilePath;
class TFx;
class TRenderSettings;
class TTile;

//=========================================================

void DVAPI loadShaderInterfaces(const TFilePath &shaderInterfacesFolder);
bool DVAPI renderShaderFxForProbe(const char *shaderName, TTile &tile,
                                  double frame, const TRenderSettings &info);
bool DVAPI renderConnectedShaderFxForProbe(const char *shaderName,
                                           TFx *input0, TFx *input1,
                                           TTile &tile, double frame,
                                           const TRenderSettings &info);
bool DVAPI renderSunflareShaderFxForProbe(TTile &tile, double frame,
                                          const TRenderSettings &info);
bool DVAPI renderSunflareShaderFxWithMetalForProbe(
    TTile &tile, double frame, const TRenderSettings &info);

#endif  // SHADERFX_H
