import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: HeliNav()));

class HeliNav extends StatefulWidget {
  const HeliNav({super.key});
  @override
  State<HeliNav> createState() => _HeliNavState();
}

class _HeliNavState extends State<HeliNav> {
  final List<LatLng> _rota = [];
  List<Map<String, dynamic>> _favoriler = [];
  final MapController _mapController = MapController();
  final TextEditingController _icaoCtrl = TextEditingController(text: "LTBI");
  final TextEditingController _nameCtrl = TextEditingController();
  
  String _metarData = "METAR Bekleniyor...";
  List<dynamic> _notamList = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('heli_v_final_secure');
    if (data != null) setState(() => _favoriler = List<Map<String, dynamic>>.from(json.decode(data)));
  }

  // HEM METAR HEM NOTAM ÇEKEN ANA FONKSİYON
  Future<void> fetchAviationData() async {
    setState(() {
      _loading = true;
      _metarData = "Veriler çekiliyor...";
      _notamList = [];
    });
    
    final icao = _icaoCtrl.text.toUpperCase();
    
    // 1. METAR Çekme (Preflight API)
    try {
      final metarRes = await http.get(
        Uri.parse('https://api.preflightapi.io/api/v1/metars/$icao'),
        headers: {'Ocp-Apim-Subscription-Key': 'c0250d2543c549f8b3a0a124751310fb'},
      );
      if (metarRes.statusCode == 200) {
        _metarData = json.decode(metarRes.body)['rawReport'] ?? "Rapor bos.";
      } else {
        _metarData = "METAR bulunamadı.";
      }
    } catch (e) { _metarData = "METAR Baglantı Hatası"; }

    // 2. SkyLink NOTAM Çekme (RapidAPI)
    try {
      final notamRes = await http.get(
        Uri.parse('https://notam-api.p.rapidapi.com/notam/$icao'),
        headers: {
          'X-RapidAPI-Key': 'eed90b7ffcmsh0b4139e55cb5613p168f5cjsn9770f1ca3dc7', // Anahtarın eklendi müdür!
          'X-RapidAPI-Host': 'notam-api.p.rapidapi.com'
        },
      );
      if (notamRes.statusCode == 200) {
        _notamList = json.decode(notamRes.body); //
      }
    } catch (e) { 
      _notamList = [{"all": "NOTAM Baglantı Hatası (İnterneti kontrol et)"}]; 
    }

    setState(() => _loading = false);
  }

  void _usKaydet(LatLng p) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Yeni Üs Kaydet"),
      content: TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: "Üs Adı")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İPTAL")),
        ElevatedButton(onPressed: () async {
          if (_nameCtrl.text.isNotEmpty) {
            setState(() => _favoriler.add({'name': _nameCtrl.text, 'lat': p.latitude, 'lon': p.longitude}));
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('heli_v_final_secure', json.encode(_favoriler));
            _nameCtrl.clear(); Navigator.pop(ctx);
          }
        }, child: const Text("KAYDET"))
      ],
    ));
  }

  void _usListesiGoster() {
    showModalBottomSheet(context: context, builder: (c) => Container(
      color: Colors.grey.shade900,
      child: ListView.builder(
        itemCount: _favoriler.length,
        itemBuilder: (c, i) => ListTile(
          leading: const Icon(Icons.location_on, color: Colors.blue),
          title: Text(_favoriler[i]['name'], style: const TextStyle(color: Colors.white)),
          onTap: () {
            _mapController.move(LatLng(_favoriler[i]['lat'], _favoriler[i]['lon']), 12);
            Navigator.pop(c);
          },
        ),
      ),
    ));
  }

  void _notamGoster() {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (c) => Container(
      height: MediaQuery.of(context).size.height * 0.75,
      color: Colors.grey.shade900,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text("GÜNCEL NOTAM LAR", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(color: Colors.white24),
          Expanded(
            child: ListView.separated(
              itemCount: _notamList.length,
              separatorBuilder: (c, i) => const Divider(color: Colors.white10),
              itemBuilder: (c, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(_notamList[i]['all'] ?? _notamList[i].toString(), 
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace')),
              ),
            ),
          ),
        ],
      ),
    ));
  }

  double get toplamNM {
    double t = 0;
    for (int i = 0; i < _rota.length - 1; i++) {
      t += const Distance().as(LengthUnit.Meter, _rota[i], _rota[i + 1]) / 1852;
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("HELI-NAV: NOTAM PRO"),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: () => setState(() => _rota.isNotEmpty ? _rota.removeLast() : null)),
          IconButton(icon: const Icon(Icons.delete_forever, color: Colors.redAccent), onPressed: () => setState(() => _rota.clear())),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(39.7, 30.5),
              initialZoom: 7,
              onTap: (pos, p) => setState(() => _rota.add(p)),
              onSecondaryTap: (pos, p) => _usKaydet(p),
              onLongPress: (pos, p) => _usKaydet(p),
            ),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
              PolylineLayer(polylines: [Polyline(points: _rota, color: Colors.blue, strokeWidth: 4)]),
              MarkerLayer(markers: [
                ..._favoriler.map((f) => Marker(point: LatLng(f['lat'], f['lon']), child: const Icon(Icons.home, color: Colors.blue, size: 24))),
                ..._rota.asMap().entries.map((e) => Marker(point: e.value, child: Icon(Icons.circle, color: e.key == 0 ? Colors.green : Colors.red, size: 10))),
              ]),
            ],
          ),
          Positioned(
            top: 10, right: 10,
            child: Container(
              width: 250, padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(8)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(child: TextField(controller: _icaoCtrl, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: const InputDecoration(isDense: true, hintText: "ICAO kodu", hintStyle: TextStyle(color: Colors.grey)))),
                  _loading ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) 
                           : IconButton(icon: const Icon(Icons.search, color: Colors.greenAccent), onPressed: fetchAviationData),
                ]),
                const Divider(color: Colors.white24),
                Text(_metarData, style: const TextStyle(color: Colors.yellowAccent, fontSize: 9, fontFamily: 'monospace')),
                if (_notamList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 30)),
                      onPressed: _notamGoster, 
                      child: Text("${_notamList.length} NOTAM'I GÖR", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        height: 100, color: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _bilgi("MESAFE", "${toplamNM.toStringAsFixed(1)} NM"),
          if (_rota.isNotEmpty)
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("${_rota.last.latitude.toStringAsFixed(4)} N", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
              Text("${_rota.last.longitude.toStringAsFixed(4)} E", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
            ])
          else
            const Text("KOORDİNAT BEKLENİYOR", style: TextStyle(color: Colors.grey, fontSize: 10)),
          ElevatedButton.icon(
            onPressed: _usListesiGoster, 
            icon: const Icon(Icons.list), 
            label: const Text("ÜSLER"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
          ),
        ]),
      ),
    );
  }

  Widget _bilgi(String t, String v) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Text(t, style: const TextStyle(color: Colors.grey, fontSize: 10)),
    Text(v, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
  ]);
}
