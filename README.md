# وتيرة — واجهة عربية حديثة للـ iPhone

**2.0.0، البناء 6، نسخة محلية بالكامل.** الملكية: **Coach : 3BIID - AB**. SwiftUI / SwiftData / Swift Charts، الحد الأدنى iOS 17. لا توجد مكتبات تطبيق خارجية أو حسابات أو خدمة خلفية. قاعدة البيانات ومنطق التمرين محفوظان؛ هذه مرحلة إعادة تصميم الواجهة وتعطيل التكاملات المؤجلة في حزمة التسليم.

معرّف التطبيق الحالي **`com.personal.Wateera`**. لا توجد امتدادات داخل IPA ولا طلبات HealthKit أو iCloud أو App Groups أو Push أو Siri أو Watch. تستخدم النسخة نفس App ID وملف provisioning الحاليين؛ لا تغيّر معرّف التوقيع المستخدم للنسخة المثبتة.

## البناء الفعلي على Mac

Xcode **16.4** وPython 3 ومحاكيات iOS مطلوبة. يستخدم مترجم Swift 6 بوضع اللغة Swift 5 المتوافق مع Swift 5.9+. المشروع مُدرج، ولا تحتاج مولّد مشروع أو Pillow للبناء.

```bash
git clone https://github.com/ghghgh5052-beep/-.git wateera-ios
cd wateera-ios
sudo xcode-select -s /Applications/Xcode_16.4.app/Contents/Developer
python3 scripts/validate_project.py
python3 scripts/tooling_tests.py
bash scripts/test_ios.sh
bash scripts/build_unsigned_ipa.sh
bash scripts/test_native_signatures.sh
```

افتح `Wateera.xcodeproj` واختر `Wateera` للعمل داخل Xcode. لا تغيّر `Config/Identifiers.xcconfig` لإعادة توقيع نفس التطبيق. توجد ثلاثة أهداف: التطبيق واختبارات الوحدة واختبارات الواجهة؛ الاختبارات لا تدخل IPA. قائمة `Config/DeferredSources.json` تحتفظ بمصادر المرحلة القديمة مستبعدةً من هذا البناء.

السكريبت الدقيق لإنتاج IPA هو [build_unsigned_ipa.sh](scripts/build_unsigned_ipa.sh). يستخدم:

```bash
xcodebuild -project Wateera.xcodeproj -scheme Wateera \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Wateera.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES archive
```

ثم ينسخ `Fitness.app` إلى `Payload/` ويضغطه إلى `build/Wateera-unsigned.ipa`. يجري فحص arm64 وZIP وغياب التوقيع والـ provisioning والامتدادات وإعدادات التكامل، ثم يصدر SHA-256 وcommit وإصدار Xcode وملف الصلاحيات الفارغ في `build/signing/`. لا توجد خطوات TestFlight أو App Store Connect. لا يستبدل السكريبت أرشيفًا سابقًا؛ استخدم مسارًا جديدًا للتكرار:

```bash
OUTPUT_DIR="$PWD/build/local-redesign-2" bash scripts/build_unsigned_ipa.sh
TEST_OUTPUT_DIR="$PWD/build/tests-2" bash scripts/test_ios.sh
```

يمكن اختيار محاكي بـ `IOS_SIMULATOR_DESTINATION='platform=iOS Simulator,id=UUID'`. إعادة توليد المشروع بعد إضافة ملف Swift: `python3 scripts/generate_project.py`. إعادة توليد أصول العلامة فقط عبر `generate_assets.py` تحتاج Pillow اختياريًا، ولا تلمس رسوم التمارين.

## CI والتسليم

[GitHub Actions](.github/workflows/ios.yml) يعمل على push والتشغيل اليدوي، على macOS 15 / Xcode 16.4. يشغّل الاختبارات على iPhone صغير ثم اختبارات الواجهة على iPhone كبير بالوضع الداكن والأرقام الغربية، ويصدر التشخيص ولقطات الشاشات، ثم IPA غير موقّع مع بيانات التحقق. لا تُرفع شهادات أو provisioning إلى المستودع أو CI.

وقّع الملف الجديد بأداتك على الآيفون. لا يوجد ويدجت يحتاج توقيعًا منفصلًا. حدّث التطبيق بنفس معرّف الحزمة دون حذف النسخة المثبتة للاحتفاظ بالبيانات؛ تتوفر نسخة احتياطية من **الإعدادات ← تصدير واستيراد ونسخ احتياطي**.

## الاستخدام

اللوحة في **التمرين** تعرض تمرين اليوم وملخص الأسبوع والسلسلة المتواصلة وأرقامك. **تقويم إنجازك** يعرض الشهر، و**تقدّمي** يعرض الرسوم الأسبوعية والشهرية والأوزان والتكرارات والأرقام والقياسات والصور. بطاقة **شارك إنجازك** متاحة من ملخص الجلسة.

الحذف: افتح جلسة سابقة ثم **حذف الجلسة** وأكّد، أو اسحب صفها إلى اليمين في RTL. إلغاء مسودة تمرين من **إلغاء التمرين دون حفظ**. يُعاد حساب التقدم والأرقام من السجلات الباقية. ملفات النسخ السابقة لا تتغير وقد تعيد الجلسة عند الاستيراد.

التذكيرات والراحة إشعارات محلية بعد إذنك. Face ID أو رمز الجهاز اختياريان. تمنع الجلسة النشطة الظاهرة انطفاء الشاشة؛ يمكنك تعطيل ذلك من الإعدادات. Quick Actions من الضغط المطوّل على أيقونة التطبيق: تمرين اليوم / تمرين حر / التقدم. كل الرسوم الستة والستين محفوظة داخل التطبيق.

## المستندات

- [ما نُفّذ وحدود التحقق](docs/UI_REDESIGN.md).
- [معرّفات النسخة الحالية وصلاحياتها والتوقيع](docs/CAPABILITIES.md).
- [الميزات المؤجلة وإعدادات حساب المطوّر لكل واحدة](docs/DEFERRED_INTEGRATIONS.md).
- [التدريب المقترح وحدود التعافي التقديري](docs/SMART_TRAINING.md)، [طرق التسجيل والتدرج](docs/TRAINING_ENHANCEMENTS.md)، [الرسوم التوضيحية](docs/EXERCISE_ART.md).
- [وصف الإصدار القديم](docs/LEGACY_OVERVIEW.md) محفوظ للتاريخ، ولا يحدد صلاحيات هذه النسخة.
