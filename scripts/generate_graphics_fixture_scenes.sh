#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${1:-/tmp/opentoonz-graphics-fixtures}"

mkdir -p "$out_dir"
mkdir -p "$out_dir/dwanko/tga"
mkdir -p "$out_dir/mesh"
mkdir -p "$out_dir/tcomposer"

ln -sf "$repo_root/doc/sample_data/dwanko/tga/A_converted.tlv" \
  "$out_dir/dwanko/tga/A_converted.tlv"
ln -sf "$repo_root/doc/sample_data/dwanko/tga/A_converted.tpl" \
  "$out_dir/dwanko/tga/A_converted.tpl"

sub_xsheet_scene="$out_dir/sub_xsheet_basic.tnz"
mesh_scene="$out_dir/mesh_skeleton_basic.tnz"
tcomposer_scene="$out_dir/tcomposer_color_card.tnz"
mesh_frame="$out_dir/mesh/basic_mesh.0001.mesh"
tcomposer_frame="$out_dir/tcomposer/color_card.0001.tif"

ln -sf "$repo_root/doc/sample_data/BG/01_sky.tif" "$tcomposer_frame"

cat >"$mesh_frame" <<'EOF'
<header>
  <version>
    1 19
  </version>
  <dpi>
    72 72
  </dpi>
  </header>
<mesh>
  <V>
    4
    -160 -120
    160 -120
    160 120
    -160 120
  </V>
  <E>
    5
    0 1
    1 2
    2 3
    3 0
    0 2
  </E>
  <F>
    2
    0 1 4
    4 2 3
  </F>
  <rigidities>
    4
    1
    0.75
    0.5
    0.75
  </rigidities>
  </mesh>
EOF

cat >"$mesh_scene" <<'EOF'
<tnz framecount="1" version="71.0">
  <generator>
    "OpenToonz graphics fixture generator"
  </generator>
  <properties>
    <cameras>
      <camera>
        <cameraSize>
          16 9
        </cameraSize>
        <cameraRes>
          1920 1080
        </cameraRes>
        <cameraXPrevalence>
          1
        </cameraXPrevalence>
        <interestRect>
          0 0 -1 -1
        </interestRect>
        </camera>
      </cameras>
    <outputs>
      <output name="main">
        <range>
          0 -1
        </range>
        <step>
          1
        </step>
        <shrink>
          1
        </shrink>
        <applyShrinkToViewer>
          0
        </applyShrinkToViewer>
        <fps>
          24
        </fps>
        <path>
          "+outputs\\.tif"
        </path>
        <bpp>
          32
        </bpp>
        <multimedia>
          0
        </multimedia>
        <threadsIndex>
          2
        </threadsIndex>
        <maxTileSizeIndex>
          0
        </maxTileSizeIndex>
        <subcameraPrev>
          0
        </subcameraPrev>
        <stereoscopic>
          0 0.05
        </stereoscopic>
        <resquality>
          0
        </resquality>
        <fieldprevalence>
          0
        </fieldprevalence>
        <gamma>
          1
        </gamma>
        <timestretch>
          25 25
        </timestretch>
      </output>
    </outputs>
    </properties>
  <levelSet>
    <levels>
      <level id='1'>
        basic_mesh
        <info dpix="72.000000" dpiy="72.000000"/>
        <path>
          "$scenefolder\\mesh\\basic_mesh.mesh"
        </path>
        </level>
    </levels>
    <folder name="Cast" type="default">
      <levels>
        <level id='1'/>
      </levels>
      </folder>
    <folder name="Audio">
      </folder>
    </levelSet>
  <xsheet>
    <columns>
      <meshColumn id='2'>
        <status>
          0
        </status>
        <cells>
          <cell>
            0 1 <level id='1'/>0001 0
          </cell>
          </cells>
      </meshColumn>
    </columns>
    <pegbars>
      <pegbar activeboth="yes" id="Camera1">
        <parent handle="B" id="None" parentHandle="B">
          </parent>
        <isOpened>
          0
        </isOpened>
        <center>
          0 0 0 0
        </center>
        <status>
          0
        </status>
        <sx>
          <default>
            1
          </default>
          </sx>
        <sy>
          <default>
            1
          </default>
          </sy>
        <sc>
          <default>
            1
          </default>
          </sc>
        <nodePos>
          24500 25550
        </nodePos>
        <camera>
          <cameraSize>
            16 9
          </cameraSize>
          <cameraRes>
            1920 1080
          </cameraRes>
          <cameraXPrevalence>
            1
          </cameraXPrevalence>
          <interestRect>
            0 0 -1 -1
          </interestRect>
          </camera>
        </pegbar>
      <pegbar id="Table">
        <parent handle="B" id="None" parentHandle="B">
          </parent>
        <isOpened>
          0
        </isOpened>
        <center>
          0 0 0 0
        </center>
        <status>
          0
        </status>
        <sx>
          <default>
            1
          </default>
          </sx>
        <sy>
          <default>
            1
          </default>
          </sy>
        <sc>
          <default>
            1
          </default>
          </sc>
        <nodePos>
          24500 25500
        </nodePos>
        </pegbar>
      <pegbar id="Col1">
        <parent handle="B" id="Table" parentHandle="B">
          </parent>
        <isOpened>
          0
        </isOpened>
        <center>
          0 0 0 0
        </center>
        <status>
          0
        </status>
        <sx>
          <default>
            1
          </default>
          </sx>
        <sy>
          <default>
            1
          </default>
          </sy>
        <sc>
          <default>
            1
          </default>
          </sc>
        <nodePos>
          24500 25400
        </nodePos>
        </pegbar>
      <grid_dimension>
        1
      </grid_dimension>
      </pegbars>
    <fxnodes>
      <xsheet>
        <Toonz_xsheetFx id='3'>
          <params>
            </params>
          <ports>
            </ports>
          <dagNodePos>
            25120 25000
          </dagNodePos>
          <numberId>
            0
          </numberId>
          <name>
            Xsheet
          </name>
          <fxId>
            ""
          </fxId>
          <opened>
            0
          </opened>
        </Toonz_xsheetFx>
        </xsheet>
      <output>
        <Toonz_outputFx id='4'>
          <params>
            </params>
          <ports>
            <source>
              <Toonz_xsheetFx id='3'/>
            </source>
            </ports>
          <dagNodePos>
            25235 24995
          </dagNodePos>
          <numberId>
            0
          </numberId>
          <name>
            Output
          </name>
          <fxId>
            ""
          </fxId>
          <opened>
            0
          </opened>
        </Toonz_outputFx>
        </output>
      <grid_dimension>
        1
      </grid_dimension>
      </fxnodes>
    </xsheet>
  <history>
    "Generated by scripts/generate_graphics_fixture_scenes.sh"
  </history>
  </tnz>
EOF

cat >"$tcomposer_scene" <<'EOF'
<tnz framecount="1" version="71.0">
  <generator>
    "OpenToonz graphics fixture generator"
  </generator>
  <properties>
    <cameras>
      <camera>
        <cameraSize>
          16 9
        </cameraSize>
        <cameraRes>
          1920 1080
        </cameraRes>
        <cameraXPrevalence>
          1
        </cameraXPrevalence>
        <interestRect>
          0 0 -1 -1
        </interestRect>
        </camera>
      </cameras>
    <outputs>
      <output name="main">
        <range>
          0 -1
        </range>
        <step>
          1
        </step>
        <shrink>
          1
        </shrink>
        <applyShrinkToViewer>
          0
        </applyShrinkToViewer>
        <fps>
          24
        </fps>
        <path>
          "+outputs\\.tif"
        </path>
        <bpp>
          32
        </bpp>
        <multimedia>
          0
        </multimedia>
        <threadsIndex>
          2
        </threadsIndex>
        <maxTileSizeIndex>
          0
        </maxTileSizeIndex>
        <subcameraPrev>
          0
        </subcameraPrev>
        <stereoscopic>
          0 0.05
        </stereoscopic>
        <resquality>
          0
        </resquality>
        <fieldprevalence>
          0
        </fieldprevalence>
        <gamma>
          1
        </gamma>
        <timestretch>
          25 25
        </timestretch>
      </output>
    </outputs>
    <bgColor>
      64 112 192 255
    </bgColor>
    </properties>
  <levelSet>
    <levels>
      <level id='1'>
        color_card
        <info dpiType="image"/>
        <path>
          "$scenefolder\\tcomposer\\color_card..tga"
        </path>
      </level>
    </levels>
    <folder name="Cast" type="default">
      <levels>
        <level id='1'/>
      </levels>
      </folder>
    <folder name="Audio">
      </folder>
    </levelSet>
  <xsheet>
    <columns>
      <levelColumn id='3'>
        <status>
          0
        </status>
        <cells>
          <cell>
            0 1 <level id='1'/>0001 0
          </cell>
          </cells>
        <fx>
          <Toonz_columnFx id='4'>
            <params>
              </params>
            <ports>
              </ports>
            <numberId>
              0
            </numberId>
            <name>
              ColorCardColumn
            </name>
            <fxId>
              ""
            </fxId>
            <opened>
              0
            </opened>
            <dagNodePos>
              25000 24900
            </dagNodePos>
          </Toonz_columnFx>
          </fx>
        </levelColumn>
    </columns>
    <pegbars>
      <pegbar activeboth="yes" id="Camera1">
        <parent handle="B" id="None" parentHandle="B">
          </parent>
        <isOpened>
          0
        </isOpened>
        <center>
          0 0 0 0
        </center>
        <status>
          0
        </status>
        <sx>
          <default>
            1
          </default>
          </sx>
        <sy>
          <default>
            1
          </default>
          </sy>
        <sc>
          <default>
            1
          </default>
          </sc>
        <nodePos>
          24500 25550
        </nodePos>
        <camera>
          <cameraSize>
            16 9
          </cameraSize>
          <cameraRes>
            1920 1080
          </cameraRes>
          <cameraXPrevalence>
            1
          </cameraXPrevalence>
          <interestRect>
            0 0 -1 -1
          </interestRect>
          </camera>
        </pegbar>
      <pegbar id="Table">
        <parent handle="B" id="None" parentHandle="B">
          </parent>
        <isOpened>
          0
        </isOpened>
        <center>
          0 0 0 0
        </center>
        <status>
          0
        </status>
        <sx>
          <default>
            1
          </default>
          </sx>
        <sy>
          <default>
            1
          </default>
          </sy>
        <sc>
          <default>
            1
          </default>
          </sc>
        <nodePos>
          24500 25500
        </nodePos>
        </pegbar>
      <grid_dimension>
        1
      </grid_dimension>
      </pegbars>
    <fxnodes>
      <terminal>
        <fxnode>
          <Toonz_columnFx id='4'/>
        </fxnode>
        </terminal>
      <xsheet>
        <Toonz_xsheetFx id='1'>
          <params>
            </params>
          <ports>
            </ports>
          <dagNodePos>
            25120 25000
          </dagNodePos>
          <numberId>
            0
          </numberId>
          <name>
            Xsheet
          </name>
          <fxId>
            ""
          </fxId>
          <opened>
            0
          </opened>
        </Toonz_xsheetFx>
        </xsheet>
      <output>
        <Toonz_outputFx id='2'>
          <params>
            </params>
          <ports>
            <source>
              <Toonz_xsheetFx id='1'/>
            </source>
            </ports>
          <dagNodePos>
            25235 24995
          </dagNodePos>
          <numberId>
            0
          </numberId>
          <name>
            Output
          </name>
          <fxId>
            ""
          </fxId>
          <opened>
            0
          </opened>
        </Toonz_outputFx>
        </output>
      <grid_dimension>
        1
      </grid_dimension>
      </fxnodes>
    </xsheet>
  <history>
    "Generated by scripts/generate_graphics_fixture_scenes.sh"
  </history>
  </tnz>
EOF

cp "$repo_root/doc/sample_data/tga_paint.tnz" "$tcomposer_scene"
perl -0pi -e \
  's#A_converted#color_card#g;
   s#"\$scenefolder/dwanko/tga/color_card\.tlv"#"\$scenefolder/tcomposer/color_card..tif"#g;
   s#0 6 <level id='\''1'\''/>0001 1#0 1 <level id='\''1'\''/>0001 0#g;
   s#"Generated by OpenToonz"|"Toonz 7.1"#"Generated by scripts/generate_graphics_fixture_scenes.sh"#g' \
  "$tcomposer_scene"

cat >"$sub_xsheet_scene" <<'EOF'
<tnz framecount="6" version="71.0">
  <generator>
    "OpenToonz graphics fixture generator"
  </generator>
  <properties>
    <cameras>
      <camera>
        <cameraSize>
          16 9
        </cameraSize>
        <cameraRes>
          1920 1080
        </cameraRes>
        <cameraXPrevalence>
          1
        </cameraXPrevalence>
        <interestRect>
          0 0 -1 -1
        </interestRect>
        </camera>
      </cameras>
    <outputs>
      <output name="main">
        <range>
          0 -1
        </range>
        <step>
          1
        </step>
        <shrink>
          1
        </shrink>
        <applyShrinkToViewer>
          0
        </applyShrinkToViewer>
        <fps>
          24
        </fps>
        <path>
          "+outputs\\.tif"
        </path>
        <bpp>
          32
        </bpp>
        <multimedia>
          0
        </multimedia>
        <threadsIndex>
          2
        </threadsIndex>
        <maxTileSizeIndex>
          0
        </maxTileSizeIndex>
        <subcameraPrev>
          0
        </subcameraPrev>
        <stereoscopic>
          0 0.05
        </stereoscopic>
        <resquality>
          0
        </resquality>
        <fieldprevalence>
          0
        </fieldprevalence>
        <gamma>
          1
        </gamma>
        <timestretch>
          25 25
        </timestretch>
      </output>
    </outputs>
    </properties>
  <levelSet>
    <levels>
      <level id='2'>
        A_converted
        <info dpiType="image"/>
        <path>
          "$scenefolder\\dwanko\\tga\\A_converted.tlv"
        </path>
      </level>
      <childLevel id='1'>
        <xsheet>
          <columns>
            <levelColumn id='3'>
              <status>
                0
              </status>
              <cells>
                <cell>
                  0 6 <level id='2'/>0001 1
                </cell>
                </cells>
              <fx>
                <Toonz_columnFx id='4'>
                  <params>
                    </params>
                  <ports>
                    </ports>
                  <numberId>
                    0
                  </numberId>
                  <name>
                    SubXsheetLevelColumn
                  </name>
                  <fxId>
                    ""
                  </fxId>
                  <opened>
                    0
                  </opened>
                </Toonz_columnFx>
              </fx>
            </levelColumn>
          </columns>
          <pegbars>
            <pegbar activeboth="yes" id="Camera1">
              <parent handle="B" id="None" parentHandle="B">
                </parent>
              <isOpened>
                0
              </isOpened>
              <center>
                0 0 0 0
              </center>
              <status>
                0
              </status>
              <sx>
                <default>
                  1
                </default>
                </sx>
              <sy>
                <default>
                  1
                </default>
                </sy>
              <sc>
                <default>
                  1
                </default>
                </sc>
              <nodePos>
                24500 25550
              </nodePos>
              <camera>
                <cameraSize>
                  16 9
                </cameraSize>
                <cameraRes>
                  1920 1080
                </cameraRes>
                <cameraXPrevalence>
                  1
                </cameraXPrevalence>
                <interestRect>
                  0 0 -1 -1
                </interestRect>
                </camera>
              </pegbar>
            <pegbar id="Table">
              <parent handle="B" id="None" parentHandle="B">
                </parent>
              <isOpened>
                0
              </isOpened>
              <center>
                0 0 0 0
              </center>
              <status>
                0
              </status>
              <sx>
                <default>
                  1
                </default>
                </sx>
              <sy>
                <default>
                  1
                </default>
                </sy>
              <sc>
                <default>
                  1
                </default>
                </sc>
              <nodePos>
                24500 25500
              </nodePos>
              </pegbar>
            <pegbar id="Col1">
              <parent handle="B" id="Table" parentHandle="B">
                </parent>
              <isOpened>
                0
              </isOpened>
              <center>
                0 0 0 0
              </center>
              <status>
                0
              </status>
              <sx>
                <default>
                  1
                </default>
                </sx>
              <sy>
                <default>
                  1
                </default>
                </sy>
              <sc>
                <default>
                  1
                </default>
                </sc>
              <nodePos>
                24500 25400
              </nodePos>
              </pegbar>
            <grid_dimension>
              1
            </grid_dimension>
            </pegbars>
          <fxnodes>
            <terminal>
              <fxnode>
                <Toonz_columnFx id='4'/>
              </fxnode>
              </terminal>
            <xsheet>
              <Toonz_xsheetFx id='5'>
                <params>
                  </params>
                <ports>
                  </ports>
                <dagNodePos>
                  25120 25000
                </dagNodePos>
                <numberId>
                  0
                </numberId>
                <name>
                  Xsheet
                </name>
                <fxId>
                  ""
                </fxId>
                <opened>
                  0
                </opened>
              </Toonz_xsheetFx>
              </xsheet>
            <output>
              <Toonz_outputFx id='6'>
                <params>
                  </params>
                <ports>
                  <source>
                    <Toonz_xsheetFx id='5'/>
                  </source>
                  </ports>
                <dagNodePos>
                  25235 24995
                </dagNodePos>
                <numberId>
                  0
                </numberId>
                <name>
                  Output
                </name>
                <fxId>
                  ""
                </fxId>
                <opened>
                  0
                </opened>
              </Toonz_outputFx>
              </output>
            <grid_dimension>
              1
            </grid_dimension>
            </fxnodes>
          </xsheet>
        <name>
          sub_xsheet_basic
        </name>
        </childLevel>
    </levels>
    <folder name="Cast" type="default">
      <levels>
        <level id='2'/>
      </levels>
      </folder>
    <folder name="Audio">
      </folder>
    </levelSet>
  <xsheet>
    <columns>
      <levelColumn id='7'>
        <status>
          0
        </status>
        <cells>
          <cell>
            0 6 <childLevel id='1'/>0001 1
          </cell>
          </cells>
        <fx>
          <Toonz_columnFx id='8'>
            <params>
              </params>
            <ports>
              </ports>
            <numberId>
              0
            </numberId>
            <name>
              ParentSubXsheetColumn
            </name>
            <fxId>
              ""
            </fxId>
            <opened>
              0
            </opened>
          </Toonz_columnFx>
        </fx>
      </levelColumn>
    </columns>
    <pegbars>
      <pegbar activeboth="yes" id="Camera1">
        <parent handle="B" id="None" parentHandle="B">
          </parent>
        <isOpened>
          0
        </isOpened>
        <center>
          0 0 0 0
        </center>
        <status>
          0
        </status>
        <sx>
          <default>
            1
          </default>
          </sx>
        <sy>
          <default>
            1
          </default>
          </sy>
        <sc>
          <default>
            1
          </default>
          </sc>
        <nodePos>
          24500 25550
        </nodePos>
        <camera>
          <cameraSize>
            16 9
          </cameraSize>
          <cameraRes>
            1920 1080
          </cameraRes>
          <cameraXPrevalence>
            1
          </cameraXPrevalence>
          <interestRect>
            0 0 -1 -1
          </interestRect>
          </camera>
        </pegbar>
      <pegbar id="Table">
        <parent handle="B" id="None" parentHandle="B">
          </parent>
        <isOpened>
          0
        </isOpened>
        <center>
          0 0 0 0
        </center>
        <status>
          0
        </status>
        <sx>
          <default>
            1
          </default>
          </sx>
        <sy>
          <default>
            1
          </default>
          </sy>
        <sc>
          <default>
            1
          </default>
          </sc>
        <nodePos>
          24500 25500
        </nodePos>
        </pegbar>
      <pegbar id="Col1">
        <parent handle="B" id="Table" parentHandle="B">
          </parent>
        <isOpened>
          0
        </isOpened>
        <center>
          0 0 0 0
        </center>
        <status>
          0
        </status>
        <sx>
          <default>
            1
          </default>
          </sx>
        <sy>
          <default>
            1
          </default>
          </sy>
        <sc>
          <default>
            1
          </default>
          </sc>
        <nodePos>
          24500 25400
        </nodePos>
        </pegbar>
      <grid_dimension>
        1
      </grid_dimension>
      </pegbars>
    <fxnodes>
      <terminal>
        <fxnode>
          <Toonz_columnFx id='8'/>
        </fxnode>
        </terminal>
      <xsheet>
        <Toonz_xsheetFx id='9'>
          <params>
            </params>
          <ports>
            </ports>
          <dagNodePos>
            25120 25000
          </dagNodePos>
          <numberId>
            0
          </numberId>
          <name>
            Xsheet
          </name>
          <fxId>
            ""
          </fxId>
          <opened>
            0
          </opened>
        </Toonz_xsheetFx>
        </xsheet>
      <output>
        <Toonz_outputFx id='10'>
          <params>
            </params>
          <ports>
            <source>
              <Toonz_xsheetFx id='9'/>
            </source>
            </ports>
          <dagNodePos>
            25235 24995
          </dagNodePos>
          <numberId>
            0
          </numberId>
          <name>
            Output
          </name>
          <fxId>
            ""
          </fxId>
          <opened>
            0
          </opened>
        </Toonz_outputFx>
        </output>
      <grid_dimension>
        1
      </grid_dimension>
      </fxnodes>
    </xsheet>
  <history>
    "Generated by scripts/generate_graphics_fixture_scenes.sh"
  </history>
  </tnz>
EOF

echo "generated $sub_xsheet_scene"
echo "generated $mesh_scene"
echo "generated $tcomposer_scene"
