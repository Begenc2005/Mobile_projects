import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Платёжная страница банка во WebView. Закрывается, когда банк возвращает на /pay/return.
class PaymentScreen extends StatefulWidget {
  final String url;
  const PaymentScreen({super.key, required this.url});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final WebViewController ctrl;
  bool loading = true;
  bool done = false;

  @override
  void initState() {
    super.initState();
    ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => loading = true),
        onPageFinished: (url) {
          setState(() => loading = false);
          // дать пользователю увидеть результат 1.5 сек и вернуться
          if (url.contains('/pay/return') && !done) {
            done = true;
            Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) Navigator.pop(context); });
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: const Row(children: [Icon(Icons.lock, size: 18), SizedBox(width: 6), Text('Altyn Asyr')]),
      ),
      body: Stack(children: [
        WebViewWidget(controller: ctrl),
        if (loading) const LinearProgressIndicator(),
      ]),
    );
  }
}
