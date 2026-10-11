# توقيع نسخة وتيرة المحلية — 2.0.0 / build 6

**هدف التسليم الوحيد: `Fitness.app`، ومعرّفه الافتراضي لم يتغيّر: `com.personal.Wateera`.** اسم التطبيق الظاهر «وتيرة». الحد الأدنى iOS 17. لا يوجد امتداد داخل IPA ولا تطبيق ساعة ولا خدمة خلفية.

ملف `Config/Fitness.entitlements` قاموس فارغ، وكذلك `Fitness.resolved.entitlements` المصدّر من إعدادات Xcode أثناء التغليف. لا تطلب هذه النسخة HealthKit أو iCloud أو CloudKit أو App Groups أو Push أو Siri. لا توجد حاويات iCloud أو مجموعات تطبيقات مستخدمة. احتفظ بمعرّف التطبيق الذي استُخدم عند توقيع نسختك المثبتة؛ لا يلزم إنشاء App ID أو تغيير provisioning لإضافة ميزات هذه النسخة.

| الهدف | معرّف الحزمة الافتراضي | ضمن IPA | صلاحيات إضافية |
|---|---|---|---|
| Fitness | `com.personal.Wateera` | نعم | لا توجد |
| FitnessTests | `com.personal.Wateera.tests` | لا، للمحاكي فقط | لا توجد |
| FitnessUITests | `com.personal.Wateera.uitests` | لا، للمحاكي فقط | لا توجد |

الملفات المصدرية القديمة للميزات المؤجلة باقية للرجوع إليها، ولكن `Config/DeferredSources.json` يستبعدها من Compile Sources. هدف FitnessWidgets غير موجود في المشروع المحلي، وملف صلاحياته القديم لا يُستخدم ولا يُضمّن. متغيرات حاويات ومجموعات المرحلة القديمة في xcconfig ليست مطالبات صلاحيات في النسخة الحالية.

## ميزات الجهاز المسموحة

| الاستخدام | إعداد التطبيق | موافقة المستخدم / توقيع |
|---|---|---|
| Face ID أو رمز الجهاز | `NSFaceIDUsageDescription` بالعربية + LocalAuthentication | موافقة نظامية عند الاستخدام، دون capability جديدة |
| تذكيرات ومؤقت الراحة | UserNotifications محلية | إذن المستخدم للتنبيه والصوت، دون `aps-environment` أو تسجيل APNs |
| صور التقدم | PhotosPicker + SwiftData محلية | منتقي النظام للصور المحددة، دون وصول شامل للمكتبة |
| مشاركة الإنجازات | ImageRenderer + UIActivityViewController | ورقة مشاركة يفتحها المستخدم، دون صلاحيات الصور أو شبكة داخل التطبيق |
| تصدير واستيراد CSV/JSON | منتقي الملفات وFileDocument | يختار المستخدم الملف والموقع |
| Haptics | UIFeedbackGenerator / sensoryFeedback | دون صلاحيات |
| إبقاء الشاشة مضاءة | `UIApplication.isIdleTimerDisabled` أثناء جلسة نشطة ظاهرة | يُلغى عند الوقف والخلفية وإنهاء الجلسة والخروج من الشاشة |
| Quick Actions | ثلاث `UIApplicationShortcutItems` + مشهد UIKit داخل دورة حياة SwiftUI | دون Siri أو امتداد |
| ProMotion | `CADisableMinimumFrameDurationOnPhone=true` | إعداد Info.plist محلي، دون capability؛ النظام يختار معدل الإطارات |

## التغليف والتحقق

تُعطّل مرحلة استخراج بيانات App Intents عبر `LM_SKIP_METADATA_EXTRACTION=YES` في إعدادات البناء المشتركة، لأن Siri مؤجل. هذا يوقف المرحلة نفسها دون إسكات تحذيرات Xcode أو ربط AppIntents بلا استخدام. مرجع الإعداد: [مصدر نظام Swift Build من Apple](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBApplePlatform/AppIntentsMetadataTaskProducer.swift).

`scripts/build_unsigned_ipa.sh` ينفّذ archive مع `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`، ويضع التطبيق وحده في Payload ثم يضغطه. لا تُستخدم أدوات App Store Connect أو TestFlight. يفحص `verify_ipa.py` arm64 وسلامة ZIP وغياب التوقيع وملف provisioning والامتدادات وإعدادات الميزات المؤجلة. يتأكد اختبار توقيع macOS من عدم طلب صلاحيات التكامل في نسخة البرنامج غير الموقعة وفي نسخة منفصلة بتوقيع ad hoc اختباري. لا يوقّع ملف التسليم.

وقّع IPA كاملًا بأداتك الحالية؛ لا يوجد امتداد يحتاج توقيعًا مستقلًا. الشهادة والفريق وصلاحيات الهوية الأساسية مثل `application-identifier` تأتي من ملف provisioning وأداة التوقيع، ولا تُختلق في المصدر. حافظ على نفس bundle identifier أثناء إعادة التوقيع والتثبيت لتحديث التطبيق مع بياناته. لا تحذف النسخة السابقة إن كنت تريد الاحتفاظ ببياناتها؛ يمكن تصدير نسخة كاملة من الإعدادات أولًا.
