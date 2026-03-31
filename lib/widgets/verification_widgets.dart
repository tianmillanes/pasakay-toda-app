import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/verification_service.dart';

class VerificationMethodSelector extends StatelessWidget {
  final VerificationType selectedType;
  final Function(VerificationType) onTypeChanged;
  final String phoneNumber;
  final String email;
  final VerificationService? verificationService;

  const VerificationMethodSelector({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
    required this.phoneNumber,
    required this.email,
    this.verificationService,
  });

  @override
  Widget build(BuildContext context) {
    final smsQuotaAvailable = verificationService?.hasSMSQuotaAvailable() ?? true;
    final remainingSMS = verificationService?.getRemainingDailySMS() ?? 10;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose Verification Method',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            RadioListTile<VerificationType>(
              title: Row(
                children: [
                  const Text('SMS (Text Message)'),
                  if (!smsQuotaAvailable) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Limit Reached',
                        style: TextStyle(fontSize: 10, color: Colors.orange),
                      ),
                    ),
                  ] else if (remainingSMS <= 3) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$remainingSMS left today',
                        style: const TextStyle(fontSize: 10, color: Colors.blue),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                smsQuotaAvailable 
                  ? 'Send code to $phoneNumber (Free: $remainingSMS/10 today)'
                  : 'Daily limit reached. Try email or wait until tomorrow.',
                style: TextStyle(
                  color: smsQuotaAvailable ? null : Colors.orange,
                ),
              ),
              value: VerificationType.sms,
              groupValue: selectedType,
              onChanged: smsQuotaAvailable ? (value) => onTypeChanged(value!) : null,
              activeColor: const Color(0xFF2D2D2D),
            ),
            RadioListTile<VerificationType>(
              title: const Row(
                children: [
                  Text('Email'),
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, size: 16, color: Colors.green),
                  SizedBox(width: 4),
                  Text(
                    'Unlimited',
                    style: TextStyle(fontSize: 10, color: Colors.green),
                  ),
                ],
              ),
              subtitle: Text('Send code to $email (Always available)'),
              value: VerificationType.email,
              groupValue: selectedType,
              onChanged: (value) => onTypeChanged(value!),
              activeColor: const Color(0xFF2D2D2D),
            ),
          ],
        ),
      ),
    );
  }
}

class VerificationCodeInput extends StatefulWidget {
  final Function(String) onCodeChanged;
  final Function() onResend;
  final bool isLoading;
  final String? errorMessage;
  final Duration? remainingTime;

  const VerificationCodeInput({
    super.key,
    required this.onCodeChanged,
    required this.onResend,
    this.isLoading = false,
    this.errorMessage,
    this.remainingTime,
  });

  @override
  State<VerificationCodeInput> createState() => _VerificationCodeInputState();
}

class _VerificationCodeInputState extends State<VerificationCodeInput> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  Timer? _timer;
  Duration? _remainingTime;

  @override
  void initState() {
    super.initState();
    _remainingTime = widget.remainingTime;
    _startTimer();
  }

  @override
  void didUpdateWidget(VerificationCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.remainingTime != oldWidget.remainingTime) {
      _remainingTime = widget.remainingTime;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (_remainingTime != null && _remainingTime!.inSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _remainingTime = _remainingTime! - const Duration(seconds: 1);
            if (_remainingTime!.inSeconds <= 0) {
              _timer?.cancel();
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.isNotEmpty) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }
    
    final code = _controllers.map((c) => c.text).join();
    widget.onCodeChanged(code);
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _remainingTime == null || _remainingTime!.inSeconds <= 0;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final fieldWidth = isMobile ? 40.0 : 50.0;
    final fieldHeight = isMobile ? 50.0 : 60.0;
    final fontSize = isMobile ? 18.0 : 24.0;
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Enter Verification Code',
              style: TextStyle(
                fontSize: isMobile ? 14 : 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please enter the 6-digit code sent to your email',
              style: TextStyle(
                color: Colors.grey,
                fontSize: isMobile ? 12 : 14,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.blue.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Check your email inbox for the verification code',
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Code input fields
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: SizedBox(
                      width: fieldWidth,
                      height: fieldHeight,
                      child: TextFormField(
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Colors.grey,
                              width: 1.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Colors.grey,
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF2D2D2D),
                              width: 2,
                            ),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            vertical: isMobile ? 8.0 : 12.0,
                            horizontal: isMobile ? 4.0 : 8.0,
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (value) => _onChanged(value, index),
                        onTap: () {
                          _controllers[index].selection = TextSelection.fromPosition(
                            TextPosition(offset: _controllers[index].text.length),
                          );
                        },
                        onFieldSubmitted: (_) {
                          if (index < 5) {
                            _focusNodes[index + 1].requestFocus();
                          }
                        },
                        onEditingComplete: () {
                          if (index < 5) {
                            _focusNodes[index + 1].requestFocus();
                          }
                        },
                      ),
                    ),
                  );
                }),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Error message
            if (widget.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  widget.errorMessage!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            
            // Resend button and timer
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Didn't receive the code? ",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: isMobile ? 12 : 14,
                    ),
                  ),
                  if (canResend)
                    TextButton(
                      onPressed: widget.isLoading ? null : widget.onResend,
                      child: widget.isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Resend',
                              style: TextStyle(
                                color: const Color(0xFF2D2D2D),
                                fontWeight: FontWeight.bold,
                                fontSize: isMobile ? 12 : 14,
                              ),
                            ),
                    )
                  else
                    Text(
                      'Resend in ${_remainingTime!.inMinutes}:${(_remainingTime!.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 12 : 14,
                      ),
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

class VerificationStatusIndicator extends StatelessWidget {
  final bool isPhoneVerified;
  final bool isEmailVerified;
  final String phoneNumber;
  final String email;

  const VerificationStatusIndicator({
    super.key,
    required this.isPhoneVerified,
    required this.isEmailVerified,
    required this.phoneNumber,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verification Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            // Phone verification status
            Row(
              children: [
                Icon(
                  isPhoneVerified ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isPhoneVerified ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Phone: $phoneNumber',
                    style: TextStyle(
                      color: isPhoneVerified ? Colors.green : Colors.grey,
                      fontWeight: isPhoneVerified ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (isPhoneVerified)
                  const Text(
                    'Verified',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Email verification status
            Row(
              children: [
                Icon(
                  isEmailVerified ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isEmailVerified ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Email: $email',
                    style: TextStyle(
                      color: isEmailVerified ? Colors.green : Colors.grey,
                      fontWeight: isEmailVerified ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (isEmailVerified)
                  const Text(
                    'Verified',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
