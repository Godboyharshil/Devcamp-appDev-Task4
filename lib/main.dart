import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const ShopApp());
}

class Product {
  final int id;
  final String title;
  final String description;
  final String category;
  final String brand;
  final double price;
  final double discountPercentage;
  final double rating;
  final int stock;
  final String thumbnail;
  final List<String> images;

  const Product({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.brand,
    required this.price,
    required this.discountPercentage,
    required this.rating,
    required this.stock,
    required this.thumbnail,
    required this.images,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      title: json['title']?.toString() ?? 'Untitled product',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Other',
      brand: json['brand']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      discountPercentage:
          (json['discountPercentage'] as num?)?.toDouble() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      thumbnail: json['thumbnail']?.toString() ?? '',
      images: (json['images'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  double get discountedPrice => price * (1 - discountPercentage / 100);
}

class ShopApp extends StatefulWidget {
  const ShopApp({super.key});

  @override
  State<ShopApp> createState() => _ShopAppState();
}

class _ShopAppState extends State<ShopApp> {
  final http.Client _client = http.Client();
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  List<Product> _products = [];
  Set<int> _favoriteIds = {};
  Map<int, int> _cart = {};
  List<String> _categories = [];
  SharedPreferences? _preferences;
  Future<void> _saveQueue = Future<void>.value();

  bool _loading = true;
  String? _error;
  int _selectedTab = 0;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  String _sortOption = 'Recommended';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      final savedCart = _preferences!.getString('shop_cart');
      final savedFavorites = _preferences!.getStringList('shop_favorites');

      if (savedCart != null) {
        final decoded = jsonDecode(savedCart) as Map<String, dynamic>;
        _cart = decoded.map((key, value) => MapEntry(
              int.parse(key),
              (value as num).toInt(),
            ));
      }

      if (savedFavorites != null) {
        _favoriteIds = savedFavorites.map(int.parse).toSet();
      }
    } catch (_) {
      _cart = {};
      _favoriteIds = {};
    }

    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final response = await _client
          .get(Uri.parse('https://dummyjson.com/products?limit=0'))
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}.');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawProducts = decoded['products'] as List<dynamic>? ?? [];
      final products = rawProducts
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .toList();
      final categories = products.map((product) => product.category).toSet().toList()
        ..sort();

      if (!mounted) return;

      setState(() {
        _products = products;
        _categories = ['All', ...categories];
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'The request timed out. Check your internet connection and retry.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load products. Check your internet connection and retry.';
      });
    }
  }

  Future<void> _persist() {
    _saveQueue = _saveQueue.then((_) async {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences!.setString(
        'shop_cart',
        jsonEncode(_cart.map((key, value) => MapEntry(key.toString(), value))),
      );
      await _preferences!.setStringList(
        'shop_favorites',
        _favoriteIds.map((id) => id.toString()).toList(),
      );
    });
    return _saveQueue;
  }

  void _toggleFavorite(Product product) {
    setState(() {
      if (_favoriteIds.contains(product.id)) {
        _favoriteIds.remove(product.id);
      } else {
        _favoriteIds.add(product.id);
      }
    });
    _persist();
  }

  void _addToCart(Product product, {int quantity = 1}) {
    final currentQuantity = _cart[product.id] ?? 0;
    if (product.stock <= currentQuantity) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('No more units of this product are available.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final nextQuantity = currentQuantity + quantity;
    setState(() {
      _cart[product.id] = nextQuantity > product.stock ? product.stock : nextQuantity;
    });
    _persist();
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('${product.title} added to cart'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _changeQuantity(Product product, int change) {
    setState(() {
      final nextQuantity = (_cart[product.id] ?? 0) + change;
      if (nextQuantity <= 0) {
        _cart.remove(product.id);
      } else {
        _cart[product.id] = nextQuantity > product.stock ? product.stock : nextQuantity;
      }
    });
    _persist();
  }

  void _removeFromCart(Product product) {
    setState(() {
      _cart.remove(product.id);
    });
    _persist();
  }

  List<Product> _filteredProducts({required bool favoritesOnly}) {
    Iterable<Product> result = _products;

    if (favoritesOnly) {
      result = result.where((product) => _favoriteIds.contains(product.id));
    }

    if (_selectedCategory != 'All' && !favoritesOnly) {
      result = result.where((product) => product.category == _selectedCategory);
    }

    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      result = result.where((product) =>
          product.title.toLowerCase().contains(query) ||
          product.brand.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query));
    }

    final products = result.toList();
    switch (_sortOption) {
      case 'Price: Low to high':
        products.sort((a, b) => a.discountedPrice.compareTo(b.discountedPrice));
        break;
      case 'Price: High to low':
        products.sort((a, b) => b.discountedPrice.compareTo(a.discountedPrice));
        break;
      case 'Top rated':
        products.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'Name: A to Z':
        products.sort((a, b) => a.title.compareTo(b.title));
        break;
    }
    return products;
  }

  Product? _productById(int id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  int get _cartItemCount => _cart.values.fold(0, (sum, quantity) => sum + quantity);

  double get _cartTotal {
    double total = 0;
    for (final entry in _cart.entries) {
      final product = _productById(entry.key);
      if (product != null) total += product.discountedPrice * entry.value;
    }
    return total;
  }

  void _openProduct(Product product) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ProductDetailsPage(
          product: product,
          isFavorite: _favoriteIds.contains(product.id),
          onFavorite: () => _toggleFavorite(product),
          onAddToCart: (quantity) => _addToCart(product, quantity: quantity),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Shoply',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F7FB),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFECECF2)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE6E5EC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE6E5EC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF6750A4), width: 1.5),
          ),
        ),
      ),
      home: Scaffold(
        body: SafeArea(child: _buildCurrentPage()),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedTab,
          onDestinationSelected: (index) {
            setState(() => _selectedTab = index);
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront),
              label: 'Shop',
            ),
            const NavigationDestination(
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite),
              label: 'Favorites',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _cartItemCount > 0,
                label: Text('$_cartItemCount'),
                child: const Icon(Icons.shopping_bag_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: _cartItemCount > 0,
                label: Text('$_cartItemCount'),
                child: const Icon(Icons.shopping_bag),
              ),
              label: 'Cart',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPage() {
    if (_loading) return _loadingView();
    if (_error != null) return _errorView();

    if (_selectedTab == 2) return _cartPage();
    if (_selectedTab == 1) return _favoritesPage();
    return _shopPage();
  }

  Widget _loadingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading products...'),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Unable to load the catalogue',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shopPage() {
    final products = _filteredProducts(favoritesOnly: false);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE7F6),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.shopping_bag, color: Color(0xFF6750A4)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SHOPLY',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: Color(0xFF6750A4),
                            ),
                          ),
                          Text(
                            'Find your next favourite',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _selectedTab = 2),
                      icon: Badge(
                        isLabelVisible: _cartItemCount > 0,
                        label: Text('$_cartItemCount'),
                        child: const Icon(Icons.shopping_bag_outlined),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Search products, brands or categories',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Categories',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _sortOption,
                        borderRadius: BorderRadius.circular(14),
                        items: const [
                          DropdownMenuItem(value: 'Recommended', child: Text('Recommended')),
                          DropdownMenuItem(value: 'Price: Low to high', child: Text('Price: Low to high')),
                          DropdownMenuItem(value: 'Price: High to low', child: Text('Price: High to low')),
                          DropdownMenuItem(value: 'Top rated', child: Text('Top rated')),
                          DropdownMenuItem(value: 'Name: A to Z', child: Text('Name: A to Z')),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _sortOption = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final selected = _selectedCategory == category;
                      return ChoiceChip(
                        label: Text(_categoryLabel(category)),
                        selected: selected,
                        onSelected: (_) => setState(() => _selectedCategory = category),
                        showCheckmark: false,
                        selectedColor: const Color(0xFFE9E1F5),
                        side: BorderSide(
                          color: selected ? const Color(0xFF6750A4) : const Color(0xFFE6E5EC),
                        ),
                        labelStyle: TextStyle(
                          color: selected ? const Color(0xFF543D8F) : Colors.black87,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        backgroundColor: Colors.white,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Popular products',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text('${products.length} items', style: const TextStyle(color: Colors.black54)),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (products.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No products match your search or filter.'),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.crossAxisExtent;
                final columns = width >= 900 ? 4 : width >= 600 ? 3 : 2;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: width >= 600 ? 0.73 : 0.63,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => ProductCard(
                      product: products[index],
                      isFavorite: _favoriteIds.contains(products[index].id),
                      onTap: () => _openProduct(products[index]),
                      onFavorite: () => _toggleFavorite(products[index]),
                      onAdd: () => _addToCart(products[index]),
                    ),
                    childCount: products.length,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _favoritesPage() {
    final products = _filteredProducts(favoritesOnly: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text('Your favorites', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
              ),
              Text('${products.length} saved', style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? _emptyState(
                  icon: Icons.favorite_border,
                  title: 'No favorites yet',
                  message: 'Save products you like and they will appear here.',
                  actionLabel: 'Explore products',
                  onAction: () => setState(() => _selectedTab = 0),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 900
                        ? 4
                        : constraints.maxWidth >= 600
                            ? 3
                            : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      itemCount: products.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: constraints.maxWidth >= 600 ? 0.73 : 0.63,
                      ),
                      itemBuilder: (context, index) => ProductCard(
                        product: products[index],
                        isFavorite: true,
                        onTap: () => _openProduct(products[index]),
                        onFavorite: () => _toggleFavorite(products[index]),
                        onAdd: () => _addToCart(products[index]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _cartPage() {
    final cartProducts = _cart.entries
        .map((entry) {
          final product = _productById(entry.key);
          if (product == null) return null;
          return CartEntry(product: product, quantity: entry.value);
        })
        .whereType<CartEntry>()
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Row(
            children: [
              const Expanded(
                child: Text('Shopping cart', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
              ),
              Text('$_cartItemCount items', style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        Expanded(
          child: cartProducts.isEmpty
              ? _emptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Your cart is empty',
                  message: 'Add something you like and it will show up here.',
                  actionLabel: 'Start shopping',
                  onAction: () => setState(() => _selectedTab = 0),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: cartProducts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final entry = cartProducts[index];
                    return CartProductTile(
                      entry: entry,
                      onIncrease: () => _changeQuantity(entry.product, 1),
                      onDecrease: () => _changeQuantity(entry.product, -1),
                      onRemove: () => _removeFromCart(entry.product),
                      onTap: () => _openProduct(entry.product),
                    );
                  },
                ),
        ),
        if (cartProducts.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFECECF2))),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Subtotal', style: TextStyle(color: Colors.black54))),
                      Text(_money(_cartTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      Text(
                        _money(_cartTotal),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF6750A4)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        showDialog<void>(
                          context: _navigatorKey.currentContext!,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Order summary'),
                            content: Text('Your mock order total is ${_money(_cartTotal)}. No payment has been taken.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                      child: const Text('Continue to checkout'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58, color: Colors.black26),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(String category) {
    if (category == 'All') return category;
    return category
        .split('-')
        .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _client.close();
    super.dispose();
  }
}

class CartEntry {
  final Product product;
  final int quantity;

  const CartEntry({required this.product, required this.quantity});
}

class ProductCard extends StatelessWidget {
  final Product product;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onAdd;

  const ProductCard({
    super.key,
    required this.product,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(url: product.thumbnail),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.white.withOpacity(0.95),
                      shape: const CircleBorder(),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: onFavorite,
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite ? Colors.redAccent : Colors.black87,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  if (product.discountPercentage > 0)
                    Positioned(
                      top: 10,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6750A4),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '${product.discountPercentage.round()}% OFF',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.brand.isEmpty ? _titleCase(product.category) : product.brand,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: Text(
                        product.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB300)),
                        const SizedBox(width: 2),
                        Text(product.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 11)),
                        const Spacer(),
                        Text(
                          _money(product.discountedPrice),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      height: 30,
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: product.stock <= 0 ? null : onAdd,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                        child: Text(
                          product.stock <= 0 ? 'Out of stock' : 'Add to cart',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductDetailsPage extends StatefulWidget {
  final Product product;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final ValueChanged<int> onAddToCart;

  const ProductDetailsPage({
    super.key,
    required this.product,
    required this.isFavorite,
    required this.onFavorite,
    required this.onAddToCart,
  });

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  int _quantity = 1;
  late bool _favorite;
  late final PageController _imageController;
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _favorite = widget.isFavorite;
    _imageController = PageController();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final images = product.images.isEmpty ? [product.thumbnail] : product.images;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: const Text('Product details', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () {
              setState(() => _favorite = !_favorite);
              widget.onFavorite();
            },
            icon: Icon(_favorite ? Icons.favorite : Icons.favorite_border),
            color: _favorite ? Colors.redAccent : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          SizedBox(
            height: 320,
            child: PageView.builder(
              controller: _imageController,
              itemCount: images.length,
              onPageChanged: (index) => setState(() => _imageIndex = index),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: ProductImage(url: images[index]),
                ),
              ),
            ),
          ),
          if (images.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  images.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _imageIndex == index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _imageIndex == index ? const Color(0xFF6750A4) : Colors.black26,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_titleCase(product.category)}${product.brand.isEmpty ? '' : '  •  ${product.brand}'}',
                  style: const TextStyle(color: Color(0xFF6750A4), fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(product.title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold, height: 1.15)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 20),
                    const SizedBox(width: 4),
                    Text('${product.rating.toStringAsFixed(1)} rating', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 14),
                    Icon(Icons.inventory_2_outlined, size: 17, color: product.stock > 0 ? Colors.green : Colors.red),
                    const SizedBox(width: 4),
                    Text(product.stock > 0 ? '${product.stock} in stock' : 'Out of stock'),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(product.discountedPrice),
                      style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold, color: Color(0xFF6750A4)),
                    ),
                    if (product.discountPercentage > 0) ...[
                      const SizedBox(width: 9),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          _money(product.price),
                          style: const TextStyle(color: Colors.black45, decoration: TextDecoration.lineThrough),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${product.discountPercentage.round()}% off',
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 22),
                const Text('Description', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(product.description, style: const TextStyle(color: Colors.black54, height: 1.55, fontSize: 14)),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const Spacer(),
                    _QuantityButton(
                      icon: Icons.remove,
                      onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                    ),
                    SizedBox(
                      width: 42,
                      child: Text('$_quantity', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    _QuantityButton(
                      icon: Icons.add,
                      onPressed: _quantity < product.stock ? () => setState(() => _quantity++) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: product.stock <= 0
                        ? null
                        : () {
                            widget.onAddToCart(_quantity);
                            Navigator.pop(context);
                          },
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: Text(product.stock <= 0 ? 'Out of stock' : 'Add ${_quantity > 1 ? '$_quantity items' : 'to cart'}'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _imageController.dispose();
    super.dispose();
  }
}

class CartProductTile extends StatelessWidget {
  final CartEntry entry;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const CartProductTile({
    super.key,
    required this.entry,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final product = entry.product;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 86,
                height: 96,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ProductImage(url: product.thumbnail),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2),
                  ),
                  const SizedBox(height: 5),
                  Text(_money(product.discountedPrice), style: const TextStyle(color: Color(0xFF6750A4), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _QuantityButton(icon: Icons.remove, onPressed: onDecrease, small: true),
                      SizedBox(
                        width: 30,
                        child: Text('${entry.quantity}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      _QuantityButton(icon: Icons.add, onPressed: onIncrease, small: true),
                      const Spacer(),
                      IconButton(
                        onPressed: onRemove,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductImage extends StatelessWidget {
  final String url;

  const ProductImage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _placeholder();
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: const Color(0xFFF2F1F6),
          alignment: Alignment.center,
          child: const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stackTrace) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFF2F1F6),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined, size: 38, color: Colors.black26),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool small;

  const _QuantityButton({
    required this.icon,
    required this.onPressed,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: small ? 28 : 34,
      height: small ? 28 : 34,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        iconSize: small ? 15 : 18,
        icon: Icon(icon),
      ),
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';

String _titleCase(String value) {
  return value
      .split(RegExp(r'[-_ ]'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
