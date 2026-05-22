set(MOC_HEADERS
    ../include/tundo.h
    ../include/tthread.h
    ../common/tcore/tthreadp.h
    ../include/tipcsrv.h
    ../include/tipcsrvP.h
    ../include/tmsgcore.h
    ../include/tfunctorinvoker.h
)

set(HEADERS ${MOC_HEADERS}
    ../common/trop/loop_macros.h
    ../common/trop/optimize_for_lp64.h
    ../common/trop/quickputP.h
    ../common/tiio/compatibility/tfile_io.h
    ../common/tiio/bmp/filebmp.h
    ../include/movsettings.h
    ../include/tconst.h
    ../include/transparencycheck.h
    ../include/trastercm.h
    ../include/trasterfx.h
    ../include/ttile.h
    ../common/psdlib/psd.h
    ../common/psdlib/psdutils.h
    ../common/trop/runsmap.h
    ../common/tvectorimage/tvectorimageP.h
    ../common/tvectorimage/tsegmentadjuster.h
    ../common/tvectorimage/tl2lautocloser.h
    ../common/tvrender/tellipticbrushP.h
    ../include/tatomicvar.h
    ../include/tcommon.h
    ../include/tconvert.h
    ../include/tdata.h
    ../include/tdebugmessage.h
    ../include/texception.h
    ../include/texpression.h
    ../include/tmathutil.h
    ../include/tnztypes.h
    ../include/tproperty.h
    ../include/trandom.h
    ../include/tsmartpointer.h
    ../include/tstopwatch.h
    ../include/tthreadmessage.h
    ../include/tutil.h
    ../include/tcolorfunctions.h
    ../include/tcolorvalue.h
    ../include/tcolumnset.h
    ../include/tpixel.h
    ../include/tpixelcm.h
    ../include/tpixelgr.h
    ../include/tpixelutils.h
    ../include/tspectrum.h
    ../include/tcurves.h
    ../include/tcurveutil.h
    ../include/tgeometry.h
    ../include/traster.h
    ../include/timage.h
    ../include/tlevel.h
    ../include/tcontenthistory.h
    ../include/tfilepath.h
    ../include/tfilepath_io.h
    ../include/tfiletype.h
    ../include/timagecache.h
    ../include/tlogger.h
    ../include/tpluginmanager.h
    ../include/tsystem.h
    ../include/drawutil.h
    ../include/tregion.h
    ../include/tstroke.h
    ../include/tstrokeoutline.h
    ../include/tsweepboundary.h
    ../include/tvectorimage.h
    ../include/tgl.h
    ../include/tgraphics.h
    ../include/tstencilcontrol.h
    ../include/tsop.h
    ../include/tsound.h
    ../include/tsound_io.h
    ../include/tsound_t.h
    ../include/tsoundsample.h
    ../include/timage_io.h
    ../include/timageinfo.h
    ../include/tlevel_io.h
    ../include/tcachedlevel.h
    ../include/tcodec.h
    ../include/trasterimage.h
    ../include/tcolorstyles.h
    ../include/tfont.h
    ../include/tinbetween.h
    ../include/tofflinegl.h
    ../include/qtofflinegl.h
    ../include/tpalette.h
    ../include/tpaletteutil.h
    ../include/tregionprop.h
    ../include/tsimplecolorstyles.h
    ../include/tstrokedeformations.h
    ../include/tstrokeprop.h
    ../include/tstrokeutil.h
    ../include/ttessellator.h
    ../include/tvectorgl.h
    ../include/tvectorbrushstyle.h
    ../include/tvectorrenderdata.h
    ../include/trop.h
    ../include/trop_borders.h
    ../include/tropcm.h
    ../include/tpersist.h
    ../include/tpersistset.h
    ../include/tstream.h
    ../include/tstreamexception.h
    ../include/tiio.h
    ../include/tiio_bmp.h
    ../include/tiio_jpg.h
    ../include/tiio_jpg_util.h
    ../include/tiio_jpg_exif.h
    ../include/tiio_std.h
    ../include/ttoonzimage.h
    ../include/tipc.h
    ../include/tipcmsg.h
    ../include/t32bitsrv_wrap.h
    ../include/tenv.h
    ../include/tmeshimage.h
    ../include/tgldisplaylistsmanager.h
    ../include/tversion.h
    ../include/tstringid.h
    ../include/tvariant.h
    ../include/tmetaimage.h
)

set(SOURCES
    ../common/tcore/tdata.cpp
    ../common/tcore/tdebugmessage.cpp
    ../common/tcore/texception.cpp
    ../common/tcore/threadmessage.cpp
    ../common/tcore/tmathutil.cpp
    ../common/tproperty.cpp
    ../common/tcore/trandom.cpp
    ../common/tcore/tsmartpointer.cpp
    ../common/tcore/tstopwatch.cpp
    ../common/tcore/tstring.cpp
    ../common/tcore/tthread.cpp
    ../common/tcore/tundo.cpp
    ../common/tcore/tfunctorinvoker.cpp
    ../common/tcolor/tcolorfunctions.cpp
    ../common/tcolor/tcolorvalue.cpp
    ../common/tcolor/tpixel.cpp
    ../common/tcolor/tpixelutils.cpp
    ../common/tcolor/tspectrum.cpp
    ../common/tgeometry/tcurves.cpp
    ../common/tgeometry/tcurveutil.cpp
    ../common/tgeometry/tgeometry.cpp
    ../common/traster/traster.cpp
    ../common/timage/timage.cpp
    ../common/timage/tlevel.cpp
    ../common/tsystem/cpuextensions.cpp
    ../common/tsystem/tbigmemorymanager.cpp
    ../common/tcontenthistory.cpp
    ../common/tsystem/tfilepath.cpp
    ../common/tsystem/tfilepath_io.cpp
    ../common/tsystem/tfiletype.cpp
    ../common/tcache/timagecache.cpp
    ../common/tsystem/tlogger.cpp
    ../common/tsystem/tpluginmanager.cpp
    ../common/tsystem/tsystem.cpp
    ../common/tvectorimage/cornerdetector.cpp
    ../common/tvectorimage/drawutil.cpp
    ../common/tvectorimage/tcomputeregions.cpp
    ../common/tvectorimage/tregion.cpp
    ../common/tvectorimage/tstroke.cpp
    ../common/tvectorimage/tstrokeoutline.cpp
    ../common/tvectorimage/tsegmentadjuster.cpp
    ../common/tvectorimage/tsweepboundary.cpp
    ../common/tvectorimage/tvectorimage.cpp
    ../common/tgraphics/tgraphics.cpp
    ../common/tgl/tgl.cpp
    ../common/tgl/tstencilcontrol.cpp
    ../common/tgl/tgldisplaylistsmanager.cpp
    ../common/tsound/tsop.cpp
    ../common/tsound/tsound.cpp
    ../common/tsound/tsound_io.cpp
    ../common/timage_io/timage_io.cpp
    ../common/timage_io/tlevel_io.cpp
    ../common/trasterimage/tcodec.cpp
    ../common/trasterimage/trasterimage.cpp
    ../common/tvrender/tcolorstyles.cpp
    ../common/tvrender/tellipticbrush.cpp
    ../common/tvrender/qtofflinegl.cpp
    ../common/tvrender/tglcurves.cpp
    ../common/tvrender/tglregions.cpp
    ../common/tvrender/tinbetween.cpp
    ../common/tvrender/tofflinegl.cpp
    ../common/tvrender/tpalette.cpp
    ../common/tvrender/tpaletteutil.cpp
    ../common/tvrender/tregionprop.cpp
    ../common/tvrender/tsimplecolorstyles.cpp
    ../common/tvrender/tstrokedeformations.cpp
    ../common/tvrender/tstrokeprop.cpp
    ../common/tvrender/tstrokeutil.cpp
    ../common/tvrender/ttessellator.cpp
    ../common/tvrender/tvectorbrush.cpp
    ../common/tvrender/tvectorbrushstyle.cpp
    ../common/psdlib/psd.cpp
    ../common/psdlib/psdutils.cpp
    ../common/trop/bbox.cpp
    ../common/trop/brush.cpp
    ../common/trop/quickput.cpp
    ../common/trop/runsmap.cpp
    ../common/trop/tantialias.cpp
    ../common/trop/tblur.cpp
    ../common/trop/tcheckboard.cpp
    ../common/trop/tconvert.cpp
    ../common/trop/tconvolve.cpp
    ../common/trop/tdespeckle.cpp
    ../common/trop/tdistancetransform.cpp
    ../common/trop/terodilate.cpp
    ../common/trop/tinvert.cpp
    ../common/trop/toperators.cpp
    ../common/trop/tover.cpp
    ../common/trop/traylit.cpp
    ../common/trop/tresample.cpp
    ../common/trop/trgbmscale.cpp
    ../common/trop/trop.cpp
    ../common/trop/tropcm.cpp
    ../common/trop/trop_borders.cpp
    ../common/tstream/tstream.cpp
    ../common/tstream/tstreamexception.cpp
    ../common/tstream/tpersistset.cpp
    ../common/tiio/tiio.cpp
    ../common/tiio/tiio_bmp.cpp
    ../common/tiio/tiio_jpg.cpp
    ../common/tiio/tiio_jpg_util.cpp
    ../common/tiio/tiio_jpg_exif.cpp
    ../common/tiio/tiio_std.cpp
    ../common/tiio/movsettings.cpp
    ../common/tiio/compatibility/tfile_io.c
    ../common/tiio/bmp/filebmp.c
    ../common/trop/tfracmove.cpp
    ../common/ttoonzimage/ttonzimage.cpp
    ../common/tsystem/uncpath.cpp
    ../common/tvectorimage/tl2lautocloser.cpp
    ../common/tvectorimage/outlineApproximation.cpp
    ../common/tipc/tipc.cpp
    ../common/tipc/tipcmsg.cpp
    ../common/tipc/tipcsrv.cpp
    ../common/tipc/t32bitsrv_wrap.cpp
    ../common/tsystem/tsystempd.cpp
    ../common/tapptools/tenv.cpp
    ../common/tmeshimage/tmeshimage.cpp
    ../common/tmsgcore.cpp
    ../common/tvrender/tfont_qt.cpp
    ../common/tmetaimage/tmetaimage.cpp
    ../common/tstringid.cpp
    ../common/tvariant.cpp
)

if(BUILD_TARGET_WIN)
    set(SOURCES ${SOURCES}
        ../common/tsound/tsound_nt.cpp
    )
elseif(BUILD_TARGET_APPLE)
    set(SOURCES ${SOURCES}
        ../common/tsound/tsound_qt.cpp
    )
    if(WITH_GRAPHICS_METAL)
        set(SOURCES ${SOURCES}
            ../common/tgraphics/tgraphics_metal.mm
            ../common/tgraphics/tgraphics_metal_shaders.metal
        )
        set_source_files_properties(
            ../common/tgraphics/tgraphics_metal_shaders.metal
            PROPERTIES HEADER_FILE_ONLY TRUE
        )

        execute_process(
            COMMAND xcrun --find metal
            OUTPUT_VARIABLE TGRAPHICS_METAL_COMPILER
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
            RESULT_VARIABLE TGRAPHICS_METAL_COMPILER_RESULT
        )
        execute_process(
            COMMAND xcrun --find metallib
            OUTPUT_VARIABLE TGRAPHICS_METALLIB_COMPILER
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
            RESULT_VARIABLE TGRAPHICS_METALLIB_COMPILER_RESULT
        )
        set(TGRAPHICS_METAL_TOOLCHAIN_RESULT 1)
        if(TGRAPHICS_METAL_COMPILER_RESULT EQUAL 0)
            execute_process(
                COMMAND "${TGRAPHICS_METAL_COMPILER}" -v
                OUTPUT_QUIET
                ERROR_QUIET
                RESULT_VARIABLE TGRAPHICS_METAL_TOOLCHAIN_RESULT
            )
        endif()

        if(TGRAPHICS_METAL_COMPILER_RESULT EQUAL 0 AND TGRAPHICS_METALLIB_COMPILER_RESULT EQUAL 0 AND TGRAPHICS_METAL_TOOLCHAIN_RESULT EQUAL 0)
            set(TGRAPHICS_METAL_SHADER_SOURCE "${CMAKE_SOURCE_DIR}/common/tgraphics/tgraphics_metal_shaders.metal")
            set(TGRAPHICS_METAL_AIR "${CMAKE_CURRENT_BINARY_DIR}/tgraphics_metal_shaders.air")
            set(TGRAPHICS_METAL_LIBRARY "${CMAKE_CURRENT_BINARY_DIR}/tgraphics_metal_shaders.metallib")
            add_custom_command(
                OUTPUT "${TGRAPHICS_METAL_LIBRARY}"
                COMMAND "${TGRAPHICS_METAL_COMPILER}" -c "${TGRAPHICS_METAL_SHADER_SOURCE}" -o "${TGRAPHICS_METAL_AIR}"
                COMMAND "${TGRAPHICS_METALLIB_COMPILER}" "${TGRAPHICS_METAL_AIR}" -o "${TGRAPHICS_METAL_LIBRARY}"
                DEPENDS "${TGRAPHICS_METAL_SHADER_SOURCE}"
                COMMENT "Compiling tgraphics Metal shader library"
                VERBATIM
            )
            add_custom_target(tgraphics_metal_shaders_metallib
                DEPENDS "${TGRAPHICS_METAL_LIBRARY}"
            )
            set_property(GLOBAL PROPERTY OPENTOONZ_TGRAPHICS_METALLIB "${TGRAPHICS_METAL_LIBRARY}")
        else()
            message(WARNING "Metal shader library tools were not found; OpenToonz will package the Metal source and use runtime shader compilation as a fallback.")
        endif()
    endif()
elseif(BUILD_TARGET_UNIX)
    set(SOURCES ${SOURCES}
        ../common/tsound/tsound_qt.cpp
    )
endif()

qt5_wrap_cpp(SOURCES ${MOC_HEADERS})

add_library(tnzcore SHARED ${HEADERS} ${SOURCES})

if(WITH_GRAPHICS_METAL)
    target_compile_definitions(tnzcore PRIVATE OPENTOONZ_WITH_GRAPHICS_METAL)
endif()

if(WITH_TRANSLATION)
    add_translation(tnzcore ${HEADERS} ${SOURCES})
    add_compile_translations_command(tnzcore tnzcore)
endif()

if(BUILD_ENV_APPLE)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-install_name,@executable_path/libtnzcore.dylib")
endif()

add_definitions(
    -DTNZCORE_EXPORTS
    -DTCOLOR_EXPORTS
    -DTGEOMETRY_EXPORTS
    -DTRASTER_EXPORTS
    -DTIMAGE_EXPORTS
    -DTSYSTEM_EXPORTS
    -DTVECTORIMAGE_EXPORTS
    -DTGL_EXPORTS
    -DTGRAPHICS_EXPORTS
    -DTSOUND_EXPORTS
    -DTIMAGE_IO_EXPORTS
    -DTRASTERIMAGE_EXPORTS
    -DTMETAIMAGE_EXPORTS
    -DTVRENDER_EXPORTS
    -DTFLASH_EXPORTS
    -DTROP_EXPORTS
    -DTSTREAM_EXPORTS
    -DTSTRINGID_EXPORTS
    -DTVARIANT_EXPORTS
)

if(BUILD_TARGET_WIN)
    add_definitions(
        -DUNICODE
        -D_UNICODE
    )
endif()

message("subdir: tnzcore")
#message("Sources:" ${SOURCES})

include_directories(
    SYSTEM
    ../common/flash
    ${SDKROOT}/Lz4/Lz4_131/lib/
)

if(BUILD_TARGET_WIN)
    if(PLATFORM EQUAL 32)
        include_directories(
            SYSTEM
            ${SDKROOT}/quicktime/QT73SDK/CIncludes
        )
    endif()
endif()


if(BUILD_ENV_MSVC)
    set(EXTRA_LIBS
        netapi32.lib
        mpr.lib
        winmm.lib
        opengl32.lib
        glu32.lib
        dbghelp.lib
    )
elseif(BUILD_ENV_APPLE)
    find_library(AUDIOUNIT_LIB AudioUnit)
    find_library(AUDIOTB_LIB AudioToolbox)
    find_library(CARBON_LIB Carbon)

    set(EXTRA_LIBS
        ${AUDIOUNIT_LIB}
        ${AUDIOTB_LIB}
        ${CARBON_LIB}
    )
    if(WITH_GRAPHICS_METAL)
        find_library(APPKIT_LIB AppKit REQUIRED)
        find_library(METAL_LIB Metal REQUIRED)
        find_library(QUARTZCORE_LIB QuartzCore REQUIRED)
        set(EXTRA_LIBS
            ${EXTRA_LIBS}
            ${APPKIT_LIB}
            ${METAL_LIB}
            ${QUARTZCORE_LIB}
        )
    endif()
elseif(BUILD_ENV_UNIXLIKE)
    if(NOT BUILD_TARGET_WIN)
        include_directories(
            SYSTEM
            ${FREETYPE_INCLUDE_DIRS}
        )
    endif()
    set(EXTRA_LIBS
        ${GLU_LIB}
    )
    if(BUILD_TARGET_WIN)
        set(EXTRA_LIBS
            ${EXTRA_LIBS}
            -lnetapi32
            -lmpr
            -lwinmm
            -lpsapi
            -ldbghelp
        )
    endif()
endif()

target_link_libraries(tnzcore
    Qt5::Core Qt5::OpenGL Qt5::Network Qt5::Multimedia
    ${GL_LIB} ${GLUT_LIB} ${QT_LIB} ${Z_LIB} ${JPEG_LIB} ${LZ4_LIB}
    ${EXTRA_LIBS}
)

if(BUILD_TARGET_APPLE AND WITH_GRAPHICS_METAL)
    add_executable(tgraphics_metal_probe
        ../common/tgraphics/tgraphics_metal_probe.cpp
    )
    target_link_libraries(tgraphics_metal_probe
        tnzcore
    )
endif()
