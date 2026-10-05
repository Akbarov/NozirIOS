/// Every sentence a parent reads, in Uzbek, copied from the Android app's
/// `res/values/strings.xml` so both apps say the same thing.
enum Copy {
    enum Welcome {
        static let title = "Bolangizning telefonini kuzatmang"
        static let body = "Nozir sizga faqat muhim narsani aytadi. Yozishmalarni hech kim oʻqimaydi — AI xulosa qiladi, siz esa nima qilish kerakligini bilasiz."
        static let benefitSummary = "Kunlik AI xulosa"
        static let benefitScreenTime = "Ekran vaqti va uyqu rejimi"
        static let benefitLocation = "Joylashuv va SOS"
        static let start = "Boshlash"
        static let haveAccount = "Hisobim bor"
        static let logoDescription = "Nozir belgisi"
    }

    enum SignIn {
        static let title = "Nozirga kirish"
        static let subtitleTelegramOnly = "Telegram orqali kiring"
        static let subtitleNoWayIn = "Hozir kirish imkoni yoʻq. Birozdan keyin qayta urinib koʻring."
        static let telegramButton = "Telegram orqali kirish"
        static let telegramWhy = "Raqamingiz Telegram orqali tasdiqlanadi. Muhim xabarlar ham shu bot orqali keladi."
        static let codeTitle = "Botdan kelgan kodni kiriting"
        static func codeSubtitle(minutes: Int) -> String {
            "Telegramda «Start» bosing, raqamingizni ulashing — bot kod yuboradi. Kod \(minutes) daqiqa amal qiladi."
        }
        static let codePlaceholder = "000000"
        static let verify = "Tasdiqlash"
        static let openBotAgain = "Botni qayta ochish"
        static let codeRejected = "Kod mos kelmadi yoki muddati tugadi. Botdan yangi kod soʻrang."
        static let telegramNotOpened = "Telegram ochilmadi. Telefoningizda Telegram oʻrnatilganini tekshiring va qayta urinib koʻring."
        static let privacyNote = "Maʼlumotlaringiz Oʻzbekiston qonunchiligiga muvofiq saqlanadi. Uchinchi shaxslarga sotilmaydi."
    }

    enum Update {
        static let title = "Ilovani yangilash kerak"
        static let body = "Bu versiya endi qoʻllab-quvvatlanmaydi. Qoidalar, tarix va farzandingizning telefoni joyida qoladi — faqat ilovani yangilash kifoya."
        static let action = "Yangilash"
        static let storeMissing = "Doʻkon ochilmadi. Ilovani App Store orqali qoʻlda yangilang."
        static func callEmergency(_ number: String) -> String {
            "Favqulodda: \(number)"
        }
        static let dialerMissing = "Qoʻngʻiroq ilovasi ochilmadi. Raqamni telefon klaviaturasida tering."
    }

    enum Home {
        static let title = "Siz Nozirga kirdingiz"
        static let body = "Asosiy ekran keyingi bosqichda quriladi."
        static let signOut = "Chiqish"
    }

    enum Errors {
        static let noConnection = "Internet aloqasi yoʻq. Ulanishni tekshirib, qayta urinib koʻring."
        static let timeout = "Server javobi juda uzoq kutildi. Qayta urinamizmi?"
        static let serviceUnavailable = "Xizmat hozir javob bermayapti. Bir necha daqiqadan keyin qayta urinamizmi?"
        static let serverProblem = "Serverda nosozlik. Bir necha daqiqadan keyin qayta urinamizmi?"
        static let sessionEnded = "Sessiya yakunlandi. Telegram orqali qaytadan kiring."
        static func rateLimited(seconds: Int?) -> String {
            guard let seconds else {
                return "Soʻrovlar juda tez ketdi. Biroz kutib, qayta urinib koʻring."
            }
            return "Soʻrovlar juda tez ketdi. \(seconds) soniyadan keyin qayta urinib koʻring."
        }
    }
}
