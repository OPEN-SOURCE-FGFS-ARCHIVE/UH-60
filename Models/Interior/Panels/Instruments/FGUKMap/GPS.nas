var DEBUG = 1;
var (width,height) = (768,512);
var tile_size = 256;
var alpha = 1;
var zoom = 11;
var gps_map = nil;
var bright = 1;

var types = [
    {
        minmaxzoom: [2,19],
        type: "intl",
        urlTemplate: "https://a.tile.openstreetmap.de/{z}/{x}/{y}.png",
        urlPath: "/osm-{type}/{z}/{x}/{y}.png"
    },
    {
        minmaxzoom: [2,14],
        type: "terrain",
        urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        urlPath: "/{z}/{x}/{y}.png"
    }
];

var currentTypeID = 0;

var show_map = func() {
    var window = canvas.new({
        "name": "GPSMap",
        "size": [width, height],
        "view": [width, height],
        "mipmapping": 1
    });

    window.addPlacement({"node": "FGBR_GPS_SCREEN"});
    var g = window.createGroup();
    g.setVisible(1);

    var type = types[currentTypeID].type;

    var ui_root = window.createGroup();
    var vbox = canvas.VBoxLayout.new();
    window.setLayout(vbox);

    var hems_seen_once = 0;

    var clamp = func(v, lo, hi) {
        return math.max(lo, math.min(hi, v));
    };

    var changeZoom = func(d) {
        if(DEBUG) print("changeZoom called with delta: ", d);
        zoom = math.max(types[currentTypeID].minmaxzoom[0], math.min(types[currentTypeID].minmaxzoom[1], zoom + d));
        updateTiles();
        if(DEBUG) print("New Zoom: ", zoom);
    };

    var changeAlpha = func(d) {
        alpha = clamp(alpha + d, 0, 1);
        window.setColorBackground(1,1,1, alpha);
    };

    var changeBright = func(d) {
        if(DEBUG) print("changeBright called with delta: ", d);
        bright = clamp(bright + d, 0, 1);
        setprop("/instrumentation/GPSMap/bright", bright);
    };

    var changeType = func() {
        if(DEBUG) print("changeType called");
        if (currentTypeID == 0) currentTypeID = 1; else currentTypeID = 0;
        type = types[currentTypeID].type;
        if (zoom > types[currentTypeID].minmaxzoom[1]) zoom = types[currentTypeID].minmaxzoom[1];
        if (zoom < types[currentTypeID].minmaxzoom[0]) zoom = types[currentTypeID].minmaxzoom[0];
        updateTiles();
    };

    var maps_base = getprop("/sim/fg-home") ~ "/cache/maps";

    foreach(var type; types) {
        type.makeUrl = string.compileTemplate(type.urlTemplate);
        type.makePath = string.compileTemplate(maps_base ~ type.urlPath);
    }

    var num_tiles = [4, 3];
    var center_tile_offset = [
        (num_tiles[0] - 1) / 2,
        (num_tiles[1] - 1) / 2
    ];

    var filename = "Aircraft/R44/Models/Interior/Panel/Instruments/RenanGPSMap/svg/boeingAirplane.svg";
    var airplane_symbol = ui_root.createChild("group");
    canvas.parsesvg(airplane_symbol, filename);
    airplane_symbol.getElementById("path3783").setColor(1,0,0);
    airplane_symbol.setTranslation(width/2, height/2);
    airplane_symbol.setScale(.5);

    var filename = "Aircraft/R44/Models/Interior/Panel/Instruments/RenanGPSMap/svg/gpslayout.svg";
    var gpslayout = ui_root.createChild("group");
    canvas.parsesvg(gpslayout, filename);
    gpslayout.setTranslation(79, height - 79);
    gpslayout.setScale(.8);

    var tiles = setsize([], num_tiles[0]);
    for (var x = 0; x < num_tiles[0]; x += 1) {
        tiles[x] = setsize([], num_tiles[1]);
        for (var y = 0; y < num_tiles[1]; y += 1) {
            tiles[x][y] = g.createChild("image", "map-tile").setSize(tile_size, tile_size);
        }
    }

    var hems_marker_shadow = g.createChild("path");
    hems_marker_shadow.setColorFill(0, 0, 0, 0.95);
    hems_marker_shadow.setStrokeLineWidth(2);
    hems_marker_shadow.set("stroke", "black");
    hems_marker_shadow.setVisible(0);

    var hems_marker = g.createChild("path");
    hems_marker.setColorFill(1, 0, 0, 1);
    hems_marker.setStrokeLineWidth(3);
    hems_marker.set("stroke", "white");
    hems_marker.setVisible(0);

    var hems_label_bg = g.createChild("path");
    hems_label_bg.setColorFill(0, 0, 0, 0.75);
    hems_label_bg.setStrokeLineWidth(2);
    hems_label_bg.set("stroke", "white");
    hems_label_bg.setVisible(0);

    var hems_text = g.createChild("text");
    hems_text.setFont("LiberationFonts/LiberationSans-Bold.ttf");
    hems_text.setFontSize(13, 1.0);
    hems_text.setColor(1, 1, 0, 1);
    hems_text.setVisible(0);

    var hems_leader = g.createChild("path");
    hems_leader.setColorFill(1, 1, 1, 0);
    hems_leader.setStrokeLineWidth(2);
    hems_leader.set("stroke", "white");
    hems_leader.setVisible(0);

    var last_tile = [-1,-1];
    var last_type = types[currentTypeID].type;

    var hide_hems_overlay = func() {
        hems_marker_shadow.setVisible(0);
        hems_marker.setVisible(0);
        hems_label_bg.setVisible(0);
        hems_text.setVisible(0);
        hems_leader.setVisible(0);
    };

    var draw_box = func(path, px, py, size) {
        var r = size / 2;
        path.reset();
        path.moveTo(px - r, py - r);
        path.lineTo(px + r, py - r);
        path.lineTo(px + r, py + r);
        path.lineTo(px - r, py + r);
        path.lineTo(px - r, py - r);
        path.close();
    };

    var draw_rect = func(path, x, y, w, h) {
        path.reset();
        path.moveTo(x, y);
        path.lineTo(x + w, y);
        path.lineTo(x + w, y + h);
        path.lineTo(x, y + h);
        path.lineTo(x, y);
        path.close();
    };

    var normalize_bearing = func(b) {
        while (b < 0) b += 360;
        while (b >= 360) b -= 360;
        return b;
    };

    var update_hems_marker = func(lat_ac, lon_ac, n) {
        var lat_hems_raw = getprop("/sim/multiplay/generic/float[120]");
        var lon_hems_raw = getprop("/sim/multiplay/generic/float[140]");

        if (lat_hems_raw == nil or lon_hems_raw == nil or lat_hems_raw == "" or lon_hems_raw == "") {
            hide_hems_overlay();
            return;
        }

        var lat_hems = num(lat_hems_raw);
        var lon_hems = num(lon_hems_raw);

        if (lat_hems == nil or lon_hems == nil or math.abs(lat_hems) > 90 or math.abs(lon_hems) > 180) {
            hide_hems_overlay();
            return;
        }

        if (!hems_seen_once) {
            print("HEMS link active: received incident coordinates ", lat_hems, ", ", lon_hems);
            hems_seen_once = 1;
        }

        var lat_hems_rad = lat_hems * math.pi / 180;
        var lat_ac_rad = lat_ac * math.pi / 180;

        var offset_hems = [
            n * ((lon_hems + 180) / 360),
            (1 - math.ln(math.tan(lat_hems_rad) + 1 / math.cos(lat_hems_rad)) / math.pi) / 2 * n
        ];

        var offset_ac_raw = [
            n * ((lon_ac + 180) / 360),
            (1 - math.ln(math.tan(lat_ac_rad) + 1 / math.cos(lat_ac_rad)) / math.pi) / 2 * n
        ];

        var dpx = (offset_hems[0] - offset_ac_raw[0]) * tile_size;
        var dpy = (offset_hems[1] - offset_ac_raw[1]) * tile_size;

        var px = width/2 + dpx;
        var py = height/2 + dpy;

        var on_screen = (px >= -30 and px <= width + 30 and py >= -30 and py <= height + 30);
        if (!on_screen) {
            hide_hems_overlay();
            if (DEBUG) print("HEMS marker off-screen px/py: ", px, "/", py);
            return;
        }

        var dlat_nm = (lat_hems - lat_ac) * 60;
        var dlon_nm = (lon_hems - lon_ac) * 60 * math.cos(lat_ac_rad);
        var dist_nm = math.sqrt(dlat_nm*dlat_nm + dlon_nm*dlon_nm);

        var bearing_deg = math.atan2(
            (lon_hems - lon_ac) * math.cos(lat_ac_rad),
            (lat_hems - lat_ac)
        ) * 180 / math.pi;
        bearing_deg = normalize_bearing(bearing_deg);

        var pulse_time = getprop("/sim/time/elapsed-sec") or 0;
        var size = 14 + int((1 + math.sin(pulse_time * 3.0)) * 2);

        draw_box(hems_marker_shadow, px + 2, py + 2, size + 6);
        hems_marker_shadow.setVisible(1);

        draw_box(hems_marker, px, py, size);
        hems_marker.setVisible(1);

        var label = sprintf("HEMS %.1fNM  %03.0f°", dist_nm, bearing_deg);

        var label_w = 220;
        var label_h = 36;
        var label_x = px + 14;
        var label_y = py - 34;

        if (label_x + label_w > width) label_x = px - label_w - 14;
        if (label_x < 0) label_x = 4;
        if (label_y < 0) label_y = py + 14;
        if (label_y + label_h > height) label_y = height - label_h - 4;

        draw_rect(hems_label_bg, label_x, label_y, label_w, label_h);
        hems_label_bg.setVisible(1);

        hems_text.setText(label);
        hems_text.setTranslation(label_x + 10, label_y + 11);
        hems_text.setVisible(1);

        hems_leader.reset();
        hems_leader.moveTo(px, py);
        if (label_x > px) {
            hems_leader.lineTo(label_x, label_y + label_h/2);
        } else {
            hems_leader.lineTo(label_x + label_w, label_y + label_h/2);
        }
        hems_leader.setVisible(1);

        if (DEBUG) {
            print("HEMS marker px/py: ", px, "/", py,
                  " (HEMS:", lat_hems, ",", lon_hems,
                  " AC:", lat_ac, ",", lon_ac,
                  " DIST:", dist_nm, "NM BRG:", bearing_deg, ")");
        }
    };

    var updateTiles = func() {
        if (getprop("/instrumentation/GPSMap/eletric") == 0) return;

        if (DEBUG) print("UpdateTiles called - Zoom: ", zoom, " Group visible: ", g.get("visible"));

        var lat = getprop("/position/latitude-deg");
        var lon = getprop("/position/longitude-deg");

        var DEG2RAD = 0.0174533;
        var hdg = getprop("/orientation/heading-deg") * DEG2RAD;
        var bearing = getprop("/instrumentation/gps/wp/wp[1]/bearing-true-deg");
        if (bearing == -9999) bearing = 0;
        bearing = bearing * DEG2RAD;

        if (DEBUG) {
            print("Heading (rad): ", hdg, " Bearing (rad): ", bearing);
            var arrow_elem = gpslayout.getElementById("arrow");
            if (arrow_elem == nil) {
                print("Error: 'arrow' element not found in gpslayout.svg");
            } else {
                print("Arrow element found, setting rotation to: ", bearing);
            }
        }

        airplane_symbol.setRotation(hdg);
        gpslayout.getElementById("arrow").setRotation(bearing);
        gpslayout.getElementById("waypoint").setText(getprop("/instrumentation/gps/wp/wp[1]/ID"));
        gpslayout.getElementById("distance").setText(int(getprop("/instrumentation/gps/wp/wp[1]/distance-nm")) ~ " NM");
        gpslayout.getElementById("hdg").setText(int(getprop("/orientation/heading-deg")) ~ "");
        gpslayout.getElementById("coords").setText(getprop("/position/latitude-string") ~ " " ~ getprop("/position/longitude-string"));

        var n = math.pow(2, zoom);
        var offset_ac = [
            n * ((lon + 180) / 360) - center_tile_offset[0],
            (1 - math.ln(math.tan(lat * math.pi/180) + 1 / math.cos(lat * math.pi/180)) / math.pi) / 2 * n - center_tile_offset[1]
        ];
        var tile_index = [int(offset_ac[0]), int(offset_ac[1])];

        var ox = tile_index[0] - offset_ac[0];
        var oy = tile_index[1] - offset_ac[1];

        update_hems_marker(lat, lon, n);

        for (var x = 0; x < num_tiles[0]; x += 1)
            for (var y = 0; y < num_tiles[1]; y += 1)
                tiles[x][y].setTranslation(
                    int((ox + x) * tile_size + 0.5),
                    int((oy + y) * tile_size + 0.5)
                );

        if (tile_index[0] != last_tile[0]
            or tile_index[1] != last_tile[1]
            or types[currentTypeID].type != last_type)
        {
            for (var x = 0; x < num_tiles[0]; x += 1)
                for (var y = 0; y < num_tiles[1]; y += 1) {
                    var pos = {
                        z: zoom,
                        x: int(offset_ac[0] + x),
                        y: int(offset_ac[1] + y),
                        type: types[currentTypeID].type
                    };

                    (func {
                        var img_path = types[currentTypeID].makePath(pos);
                        var tile = tiles[x][y];

                        if (io.stat(img_path) == nil) {
                            var img_url = types[currentTypeID].makeUrl(pos);
                            http.save(img_url, img_path)
                                .done(func {
                                    tile.set("src", img_path);
                                    tile.setVisible(1);
                                })
                                .fail(func(r) { });
                        } else {
                            tile.set("src", img_path);
                            tile.setVisible(1);
                        }
                    })();
                }

            last_tile = tile_index;
            last_type = type;
        }
    };

    var update_timer = maketimer(2, updateTiles);
    update_timer.start();

    changeZoom(0);

    window.del = func() {
        print("Cleaning up GPSMap window");
        update_timer.stop();
        call(canvas.Window.del, [], me);
    };

    return {
        window: window,
        changeZoom: changeZoom,
        changeAlpha: changeAlpha,
        changeBright: changeBright,
        changeType: changeType,
        updateTiles: updateTiles
    };
};

gps_map = show_map();

var fdm_init_listener = _setlistener("/sim/signals/fdm-initialized", func {
    removelistener(fdm_init_listener);
    setprop("/instrumentation/GPSMap/eletric", 0);
    setprop("/instrumentation/GPSMap/bright", 1);
});
