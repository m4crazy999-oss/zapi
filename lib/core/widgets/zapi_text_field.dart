import 'package:flutter/material.dart';

class ZapiTextField extends StatefulWidget {
  const ZapiTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.prefixText,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.maxLength,
    this.maxLines = 1,
    this.onChanged,
    this.onFieldSubmitted,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final String? prefixText;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final int? maxLength;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<ZapiTextField> createState() => _ZapiTextFieldState();
}

class _ZapiTextFieldState extends State<ZapiTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      validator: widget.validator,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      obscureText: _obscured,
      enabled: widget.enabled,
      maxLength: widget.maxLength,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixText: widget.prefixText,
        prefixIcon: widget.prefixIcon != null ? Icon(widget.prefixIcon) : null,
        suffixIcon: widget.obscureText
            ? IconButton(
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                tooltip: _obscured ? 'Mostrar senha' : 'Ocultar senha',
              )
            : null,
      ),
    );
  }
}
