import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class Item {
  int? id;
  String name;
  int stock;
  int onhand;
  String? imagePath;

  Item({
    this.id,
    required this.name,
    this.stock = 0,
    this.onhand = 0,
    this.imagePath,
  });

  int get variance => stock - onhand;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'stock': stock,
      'onhand': onhand,
      'imagePath': imagePath,
    };
  }

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      id: map['id'],
      name: map['name'],
      stock: map['stock'],
      onhand: map['onhand'],
      imagePath: map['imagePath'],
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Cafe Inventory",
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.brown,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Database? db;
  List<Item> items = [];
  List<Item> filteredItems = [];

  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    initDB();
  }

  Future<void> initDB() async {
    final dbPath = await getDatabasesPath();

    db = await openDatabase(
      '$dbPath/inventory.db',
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            stock INTEGER,
            onhand INTEGER,
            imagePath TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Handle older DBs that may not have the expected columns.
        // We use safe ALTERs so upgrades don't fail.
        final cols = await db.rawQuery('PRAGMA table_info(items)');
        final existing = cols.map((e) => e['name']?.toString()).toSet();

        if (!existing.contains('stock')) {
          await db.execute('ALTER TABLE items ADD COLUMN stock INTEGER');
        }
        if (!existing.contains('onhand')) {
          await db.execute('ALTER TABLE items ADD COLUMN onhand INTEGER');
        }
        if (!existing.contains('imagePath')) {
          await db.execute('ALTER TABLE items ADD COLUMN imagePath TEXT');
        }
      },
    );

    loadItems();
  }

  Future<void> loadItems() async {
    if (db == null) return;

    final maps = await db!.query('items');

    items = maps.map((e) => Item.fromMap(e)).toList();

    filteredItems = items;

    setState(() {});
  }

  Future<void> addItem(String name) async {
    if (db == null) return;

    await db!.insert(
      'items',
      Item(name: name).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await loadItems();
  }

  Future<void> updateItem(Item item) async {
    await db!.update(
      'items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );

    loadItems();
  }

  Future<void> deleteItem(int id) async {
    await db!.delete(
      'items',
      where: 'id = ?',
      whereArgs: [id],
    );

    loadItems();
  }

  void searchItems(String query) {
    filteredItems = items.where((item) {
      return item.name.toLowerCase().contains(query.toLowerCase());
    }).toList();

    setState(() {});
  }

  Future<void> addItemDialog() async {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Add Item"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: "Item name",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (controller.text.trim().isEmpty) return;

                await addItem(controller.text.trim());

                if (!mounted) return;

                Navigator.pop(dialogContext);
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  Future<void> editNumberDialog(Item item, String field) async {
    final controller = TextEditingController(
      text: field == "stock"
          ? item.stock.toString()
          : item.onhand.toString(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text("Edit ${field.toUpperCase()}"),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                int value = int.tryParse(controller.text) ?? 0;

                if (field == "stock") {
                  item.stock = value;
                } else {
                  item.onhand = value;
                }

                await updateItem(item);

                if (!mounted) return;

                Navigator.pop(dialogContext);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Future<void> pickImage(Item item) async {
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 60,
    );

    if (image == null) return;

    final appDir = await getApplicationDocumentsDirectory();

    final fileName = image.name;

    final savedImage = await File(image.path).copy(
      '${appDir.path}/$fileName',
    );

    item.imagePath = savedImage.path;

    await updateItem(item);
  }

  Widget numberEditor({
    required Item item,
    required String field,
    required int value,
  }) {
    return Expanded(
      flex: 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onLongPress: () {
              editNumberDialog(item, field);
            },
            child: Text(
              value.toString(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
              ),
            ),
          ),

          const SizedBox(height: 6),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                onTap: () async {
                  if (field == "stock") {
                    item.stock++;
                  } else {
                    item.onhand++;
                  }

                  await updateItem(item);
                },
                child: const Icon(
                  Icons.add_box,
                  color: Colors.green,
                ),
              ),

              const SizedBox(width: 8),

              InkWell(
                onTap: () async {
                  if (field == "stock") {
                    if (item.stock > 0) item.stock--;
                  } else {
                    if (item.onhand > 0) item.onhand--;
                  }

                  await updateItem(item);
                },
                child: const Icon(
                  Icons.indeterminate_check_box,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("CAFE INVENTORY"),
        centerTitle: true,
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: addItemDialog,
        child: const Icon(Icons.add),
      ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: searchItems,
              decoration: const InputDecoration(
                hintText: "Search item...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 8,
            ),
            color: Colors.brown.shade100,
            child: const Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    "PRODUCT",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      "STOCK",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      "ONHAND",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                Expanded(
                  flex: 1,
                  child: Center(
                    child: Text(
                      "VAR",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.builder(
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                final item = filteredItems[index];

                return Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ),

                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                deleteItem(item.id!);
                              },
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.red,
                              ),
                            ),

                            GestureDetector(
                              onTap: () {
                                pickImage(item);
                              },
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: item.imagePath == null
                                    ? const Icon(Icons.camera_alt)
                                    : ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        child: Image.file(
                                          File(item.imagePath!),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      numberEditor(
                        item: item,
                        field: "stock",
                        value: item.stock,
                      ),

                      numberEditor(
                        item: item,
                        field: "onhand",
                        value: item.onhand,
                      ),

                      Expanded(
                        flex: 1,
                        child: Center(
                          child: Text(
                            item.variance.toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: item.variance < 0
                                  ? Colors.red
                                  : item.variance > 0
                                      ? Colors.blue
                                      : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}