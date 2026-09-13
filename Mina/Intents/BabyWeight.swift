import AppIntents
import Foundation

/// Spoken weights for "Mina weighs 7 pounds 4 ounces". One case per ounce
/// from 5 lb to 15 lb 15 oz, generated so Siri can match them offline.
enum BabyWeight: String, AppEnum {
    case lb5oz0, lb5oz1, lb5oz2, lb5oz3, lb5oz4, lb5oz5, lb5oz6, lb5oz7
    case lb5oz8, lb5oz9, lb5oz10, lb5oz11, lb5oz12, lb5oz13, lb5oz14, lb5oz15
    case lb6oz0, lb6oz1, lb6oz2, lb6oz3, lb6oz4, lb6oz5, lb6oz6, lb6oz7
    case lb6oz8, lb6oz9, lb6oz10, lb6oz11, lb6oz12, lb6oz13, lb6oz14, lb6oz15
    case lb7oz0, lb7oz1, lb7oz2, lb7oz3, lb7oz4, lb7oz5, lb7oz6, lb7oz7
    case lb7oz8, lb7oz9, lb7oz10, lb7oz11, lb7oz12, lb7oz13, lb7oz14, lb7oz15
    case lb8oz0, lb8oz1, lb8oz2, lb8oz3, lb8oz4, lb8oz5, lb8oz6, lb8oz7
    case lb8oz8, lb8oz9, lb8oz10, lb8oz11, lb8oz12, lb8oz13, lb8oz14, lb8oz15
    case lb9oz0, lb9oz1, lb9oz2, lb9oz3, lb9oz4, lb9oz5, lb9oz6, lb9oz7
    case lb9oz8, lb9oz9, lb9oz10, lb9oz11, lb9oz12, lb9oz13, lb9oz14, lb9oz15
    case lb10oz0, lb10oz1, lb10oz2, lb10oz3, lb10oz4, lb10oz5, lb10oz6, lb10oz7
    case lb10oz8, lb10oz9, lb10oz10, lb10oz11, lb10oz12, lb10oz13, lb10oz14, lb10oz15
    case lb11oz0, lb11oz1, lb11oz2, lb11oz3, lb11oz4, lb11oz5, lb11oz6, lb11oz7
    case lb11oz8, lb11oz9, lb11oz10, lb11oz11, lb11oz12, lb11oz13, lb11oz14, lb11oz15
    case lb12oz0, lb12oz1, lb12oz2, lb12oz3, lb12oz4, lb12oz5, lb12oz6, lb12oz7
    case lb12oz8, lb12oz9, lb12oz10, lb12oz11, lb12oz12, lb12oz13, lb12oz14, lb12oz15
    case lb13oz0, lb13oz1, lb13oz2, lb13oz3, lb13oz4, lb13oz5, lb13oz6, lb13oz7
    case lb13oz8, lb13oz9, lb13oz10, lb13oz11, lb13oz12, lb13oz13, lb13oz14, lb13oz15
    case lb14oz0, lb14oz1, lb14oz2, lb14oz3, lb14oz4, lb14oz5, lb14oz6, lb14oz7
    case lb14oz8, lb14oz9, lb14oz10, lb14oz11, lb14oz12, lb14oz13, lb14oz14, lb14oz15
    case lb15oz0, lb15oz1, lb15oz2, lb15oz3, lb15oz4, lb15oz5, lb15oz6, lb15oz7
    case lb15oz8, lb15oz9, lb15oz10, lb15oz11, lb15oz12, lb15oz13, lb15oz14, lb15oz15

    // MARK: Spoken forms

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Weight")

    static var caseDisplayRepresentations: [BabyWeight: DisplayRepresentation] = [
        .lb5oz0: DisplayRepresentation(title: "5 pounds", synonyms: ["5 lb", "5 pounds 0 ounces", "5 pounds even"]),
        .lb5oz1: DisplayRepresentation(title: "5 pounds 1 ounce", synonyms: ["5 lb 1 oz", "5 pounds and 1 ounce", "5 1"]),
        .lb5oz2: DisplayRepresentation(title: "5 pounds 2 ounces", synonyms: ["5 lb 2 oz", "5 pounds and 2 ounces", "5 2"]),
        .lb5oz3: DisplayRepresentation(title: "5 pounds 3 ounces", synonyms: ["5 lb 3 oz", "5 pounds and 3 ounces", "5 3"]),
        .lb5oz4: DisplayRepresentation(title: "5 pounds 4 ounces", synonyms: ["5 lb 4 oz", "5 pounds and 4 ounces", "5 4"]),
        .lb5oz5: DisplayRepresentation(title: "5 pounds 5 ounces", synonyms: ["5 lb 5 oz", "5 pounds and 5 ounces", "5 5"]),
        .lb5oz6: DisplayRepresentation(title: "5 pounds 6 ounces", synonyms: ["5 lb 6 oz", "5 pounds and 6 ounces", "5 6"]),
        .lb5oz7: DisplayRepresentation(title: "5 pounds 7 ounces", synonyms: ["5 lb 7 oz", "5 pounds and 7 ounces", "5 7"]),
        .lb5oz8: DisplayRepresentation(title: "5 pounds 8 ounces", synonyms: ["5 lb 8 oz", "5 pounds and 8 ounces", "5 8"]),
        .lb5oz9: DisplayRepresentation(title: "5 pounds 9 ounces", synonyms: ["5 lb 9 oz", "5 pounds and 9 ounces", "5 9"]),
        .lb5oz10: DisplayRepresentation(title: "5 pounds 10 ounces", synonyms: ["5 lb 10 oz", "5 pounds and 10 ounces", "5 10"]),
        .lb5oz11: DisplayRepresentation(title: "5 pounds 11 ounces", synonyms: ["5 lb 11 oz", "5 pounds and 11 ounces", "5 11"]),
        .lb5oz12: DisplayRepresentation(title: "5 pounds 12 ounces", synonyms: ["5 lb 12 oz", "5 pounds and 12 ounces", "5 12"]),
        .lb5oz13: DisplayRepresentation(title: "5 pounds 13 ounces", synonyms: ["5 lb 13 oz", "5 pounds and 13 ounces", "5 13"]),
        .lb5oz14: DisplayRepresentation(title: "5 pounds 14 ounces", synonyms: ["5 lb 14 oz", "5 pounds and 14 ounces", "5 14"]),
        .lb5oz15: DisplayRepresentation(title: "5 pounds 15 ounces", synonyms: ["5 lb 15 oz", "5 pounds and 15 ounces", "5 15"]),
        .lb6oz0: DisplayRepresentation(title: "6 pounds", synonyms: ["6 lb", "6 pounds 0 ounces", "6 pounds even"]),
        .lb6oz1: DisplayRepresentation(title: "6 pounds 1 ounce", synonyms: ["6 lb 1 oz", "6 pounds and 1 ounce", "6 1"]),
        .lb6oz2: DisplayRepresentation(title: "6 pounds 2 ounces", synonyms: ["6 lb 2 oz", "6 pounds and 2 ounces", "6 2"]),
        .lb6oz3: DisplayRepresentation(title: "6 pounds 3 ounces", synonyms: ["6 lb 3 oz", "6 pounds and 3 ounces", "6 3"]),
        .lb6oz4: DisplayRepresentation(title: "6 pounds 4 ounces", synonyms: ["6 lb 4 oz", "6 pounds and 4 ounces", "6 4"]),
        .lb6oz5: DisplayRepresentation(title: "6 pounds 5 ounces", synonyms: ["6 lb 5 oz", "6 pounds and 5 ounces", "6 5"]),
        .lb6oz6: DisplayRepresentation(title: "6 pounds 6 ounces", synonyms: ["6 lb 6 oz", "6 pounds and 6 ounces", "6 6"]),
        .lb6oz7: DisplayRepresentation(title: "6 pounds 7 ounces", synonyms: ["6 lb 7 oz", "6 pounds and 7 ounces", "6 7"]),
        .lb6oz8: DisplayRepresentation(title: "6 pounds 8 ounces", synonyms: ["6 lb 8 oz", "6 pounds and 8 ounces", "6 8"]),
        .lb6oz9: DisplayRepresentation(title: "6 pounds 9 ounces", synonyms: ["6 lb 9 oz", "6 pounds and 9 ounces", "6 9"]),
        .lb6oz10: DisplayRepresentation(title: "6 pounds 10 ounces", synonyms: ["6 lb 10 oz", "6 pounds and 10 ounces", "6 10"]),
        .lb6oz11: DisplayRepresentation(title: "6 pounds 11 ounces", synonyms: ["6 lb 11 oz", "6 pounds and 11 ounces", "6 11"]),
        .lb6oz12: DisplayRepresentation(title: "6 pounds 12 ounces", synonyms: ["6 lb 12 oz", "6 pounds and 12 ounces", "6 12"]),
        .lb6oz13: DisplayRepresentation(title: "6 pounds 13 ounces", synonyms: ["6 lb 13 oz", "6 pounds and 13 ounces", "6 13"]),
        .lb6oz14: DisplayRepresentation(title: "6 pounds 14 ounces", synonyms: ["6 lb 14 oz", "6 pounds and 14 ounces", "6 14"]),
        .lb6oz15: DisplayRepresentation(title: "6 pounds 15 ounces", synonyms: ["6 lb 15 oz", "6 pounds and 15 ounces", "6 15"]),
        .lb7oz0: DisplayRepresentation(title: "7 pounds", synonyms: ["7 lb", "7 pounds 0 ounces", "7 pounds even"]),
        .lb7oz1: DisplayRepresentation(title: "7 pounds 1 ounce", synonyms: ["7 lb 1 oz", "7 pounds and 1 ounce", "7 1"]),
        .lb7oz2: DisplayRepresentation(title: "7 pounds 2 ounces", synonyms: ["7 lb 2 oz", "7 pounds and 2 ounces", "7 2"]),
        .lb7oz3: DisplayRepresentation(title: "7 pounds 3 ounces", synonyms: ["7 lb 3 oz", "7 pounds and 3 ounces", "7 3"]),
        .lb7oz4: DisplayRepresentation(title: "7 pounds 4 ounces", synonyms: ["7 lb 4 oz", "7 pounds and 4 ounces", "7 4"]),
        .lb7oz5: DisplayRepresentation(title: "7 pounds 5 ounces", synonyms: ["7 lb 5 oz", "7 pounds and 5 ounces", "7 5"]),
        .lb7oz6: DisplayRepresentation(title: "7 pounds 6 ounces", synonyms: ["7 lb 6 oz", "7 pounds and 6 ounces", "7 6"]),
        .lb7oz7: DisplayRepresentation(title: "7 pounds 7 ounces", synonyms: ["7 lb 7 oz", "7 pounds and 7 ounces", "7 7"]),
        .lb7oz8: DisplayRepresentation(title: "7 pounds 8 ounces", synonyms: ["7 lb 8 oz", "7 pounds and 8 ounces", "7 8"]),
        .lb7oz9: DisplayRepresentation(title: "7 pounds 9 ounces", synonyms: ["7 lb 9 oz", "7 pounds and 9 ounces", "7 9"]),
        .lb7oz10: DisplayRepresentation(title: "7 pounds 10 ounces", synonyms: ["7 lb 10 oz", "7 pounds and 10 ounces", "7 10"]),
        .lb7oz11: DisplayRepresentation(title: "7 pounds 11 ounces", synonyms: ["7 lb 11 oz", "7 pounds and 11 ounces", "7 11"]),
        .lb7oz12: DisplayRepresentation(title: "7 pounds 12 ounces", synonyms: ["7 lb 12 oz", "7 pounds and 12 ounces", "7 12"]),
        .lb7oz13: DisplayRepresentation(title: "7 pounds 13 ounces", synonyms: ["7 lb 13 oz", "7 pounds and 13 ounces", "7 13"]),
        .lb7oz14: DisplayRepresentation(title: "7 pounds 14 ounces", synonyms: ["7 lb 14 oz", "7 pounds and 14 ounces", "7 14"]),
        .lb7oz15: DisplayRepresentation(title: "7 pounds 15 ounces", synonyms: ["7 lb 15 oz", "7 pounds and 15 ounces", "7 15"]),
        .lb8oz0: DisplayRepresentation(title: "8 pounds", synonyms: ["8 lb", "8 pounds 0 ounces", "8 pounds even"]),
        .lb8oz1: DisplayRepresentation(title: "8 pounds 1 ounce", synonyms: ["8 lb 1 oz", "8 pounds and 1 ounce", "8 1"]),
        .lb8oz2: DisplayRepresentation(title: "8 pounds 2 ounces", synonyms: ["8 lb 2 oz", "8 pounds and 2 ounces", "8 2"]),
        .lb8oz3: DisplayRepresentation(title: "8 pounds 3 ounces", synonyms: ["8 lb 3 oz", "8 pounds and 3 ounces", "8 3"]),
        .lb8oz4: DisplayRepresentation(title: "8 pounds 4 ounces", synonyms: ["8 lb 4 oz", "8 pounds and 4 ounces", "8 4"]),
        .lb8oz5: DisplayRepresentation(title: "8 pounds 5 ounces", synonyms: ["8 lb 5 oz", "8 pounds and 5 ounces", "8 5"]),
        .lb8oz6: DisplayRepresentation(title: "8 pounds 6 ounces", synonyms: ["8 lb 6 oz", "8 pounds and 6 ounces", "8 6"]),
        .lb8oz7: DisplayRepresentation(title: "8 pounds 7 ounces", synonyms: ["8 lb 7 oz", "8 pounds and 7 ounces", "8 7"]),
        .lb8oz8: DisplayRepresentation(title: "8 pounds 8 ounces", synonyms: ["8 lb 8 oz", "8 pounds and 8 ounces", "8 8"]),
        .lb8oz9: DisplayRepresentation(title: "8 pounds 9 ounces", synonyms: ["8 lb 9 oz", "8 pounds and 9 ounces", "8 9"]),
        .lb8oz10: DisplayRepresentation(title: "8 pounds 10 ounces", synonyms: ["8 lb 10 oz", "8 pounds and 10 ounces", "8 10"]),
        .lb8oz11: DisplayRepresentation(title: "8 pounds 11 ounces", synonyms: ["8 lb 11 oz", "8 pounds and 11 ounces", "8 11"]),
        .lb8oz12: DisplayRepresentation(title: "8 pounds 12 ounces", synonyms: ["8 lb 12 oz", "8 pounds and 12 ounces", "8 12"]),
        .lb8oz13: DisplayRepresentation(title: "8 pounds 13 ounces", synonyms: ["8 lb 13 oz", "8 pounds and 13 ounces", "8 13"]),
        .lb8oz14: DisplayRepresentation(title: "8 pounds 14 ounces", synonyms: ["8 lb 14 oz", "8 pounds and 14 ounces", "8 14"]),
        .lb8oz15: DisplayRepresentation(title: "8 pounds 15 ounces", synonyms: ["8 lb 15 oz", "8 pounds and 15 ounces", "8 15"]),
        .lb9oz0: DisplayRepresentation(title: "9 pounds", synonyms: ["9 lb", "9 pounds 0 ounces", "9 pounds even"]),
        .lb9oz1: DisplayRepresentation(title: "9 pounds 1 ounce", synonyms: ["9 lb 1 oz", "9 pounds and 1 ounce", "9 1"]),
        .lb9oz2: DisplayRepresentation(title: "9 pounds 2 ounces", synonyms: ["9 lb 2 oz", "9 pounds and 2 ounces", "9 2"]),
        .lb9oz3: DisplayRepresentation(title: "9 pounds 3 ounces", synonyms: ["9 lb 3 oz", "9 pounds and 3 ounces", "9 3"]),
        .lb9oz4: DisplayRepresentation(title: "9 pounds 4 ounces", synonyms: ["9 lb 4 oz", "9 pounds and 4 ounces", "9 4"]),
        .lb9oz5: DisplayRepresentation(title: "9 pounds 5 ounces", synonyms: ["9 lb 5 oz", "9 pounds and 5 ounces", "9 5"]),
        .lb9oz6: DisplayRepresentation(title: "9 pounds 6 ounces", synonyms: ["9 lb 6 oz", "9 pounds and 6 ounces", "9 6"]),
        .lb9oz7: DisplayRepresentation(title: "9 pounds 7 ounces", synonyms: ["9 lb 7 oz", "9 pounds and 7 ounces", "9 7"]),
        .lb9oz8: DisplayRepresentation(title: "9 pounds 8 ounces", synonyms: ["9 lb 8 oz", "9 pounds and 8 ounces", "9 8"]),
        .lb9oz9: DisplayRepresentation(title: "9 pounds 9 ounces", synonyms: ["9 lb 9 oz", "9 pounds and 9 ounces", "9 9"]),
        .lb9oz10: DisplayRepresentation(title: "9 pounds 10 ounces", synonyms: ["9 lb 10 oz", "9 pounds and 10 ounces", "9 10"]),
        .lb9oz11: DisplayRepresentation(title: "9 pounds 11 ounces", synonyms: ["9 lb 11 oz", "9 pounds and 11 ounces", "9 11"]),
        .lb9oz12: DisplayRepresentation(title: "9 pounds 12 ounces", synonyms: ["9 lb 12 oz", "9 pounds and 12 ounces", "9 12"]),
        .lb9oz13: DisplayRepresentation(title: "9 pounds 13 ounces", synonyms: ["9 lb 13 oz", "9 pounds and 13 ounces", "9 13"]),
        .lb9oz14: DisplayRepresentation(title: "9 pounds 14 ounces", synonyms: ["9 lb 14 oz", "9 pounds and 14 ounces", "9 14"]),
        .lb9oz15: DisplayRepresentation(title: "9 pounds 15 ounces", synonyms: ["9 lb 15 oz", "9 pounds and 15 ounces", "9 15"]),
        .lb10oz0: DisplayRepresentation(title: "10 pounds", synonyms: ["10 lb", "10 pounds 0 ounces", "10 pounds even"]),
        .lb10oz1: DisplayRepresentation(title: "10 pounds 1 ounce", synonyms: ["10 lb 1 oz", "10 pounds and 1 ounce", "10 1"]),
        .lb10oz2: DisplayRepresentation(title: "10 pounds 2 ounces", synonyms: ["10 lb 2 oz", "10 pounds and 2 ounces", "10 2"]),
        .lb10oz3: DisplayRepresentation(title: "10 pounds 3 ounces", synonyms: ["10 lb 3 oz", "10 pounds and 3 ounces", "10 3"]),
        .lb10oz4: DisplayRepresentation(title: "10 pounds 4 ounces", synonyms: ["10 lb 4 oz", "10 pounds and 4 ounces", "10 4"]),
        .lb10oz5: DisplayRepresentation(title: "10 pounds 5 ounces", synonyms: ["10 lb 5 oz", "10 pounds and 5 ounces", "10 5"]),
        .lb10oz6: DisplayRepresentation(title: "10 pounds 6 ounces", synonyms: ["10 lb 6 oz", "10 pounds and 6 ounces", "10 6"]),
        .lb10oz7: DisplayRepresentation(title: "10 pounds 7 ounces", synonyms: ["10 lb 7 oz", "10 pounds and 7 ounces", "10 7"]),
        .lb10oz8: DisplayRepresentation(title: "10 pounds 8 ounces", synonyms: ["10 lb 8 oz", "10 pounds and 8 ounces", "10 8"]),
        .lb10oz9: DisplayRepresentation(title: "10 pounds 9 ounces", synonyms: ["10 lb 9 oz", "10 pounds and 9 ounces", "10 9"]),
        .lb10oz10: DisplayRepresentation(title: "10 pounds 10 ounces", synonyms: ["10 lb 10 oz", "10 pounds and 10 ounces", "10 10"]),
        .lb10oz11: DisplayRepresentation(title: "10 pounds 11 ounces", synonyms: ["10 lb 11 oz", "10 pounds and 11 ounces", "10 11"]),
        .lb10oz12: DisplayRepresentation(title: "10 pounds 12 ounces", synonyms: ["10 lb 12 oz", "10 pounds and 12 ounces", "10 12"]),
        .lb10oz13: DisplayRepresentation(title: "10 pounds 13 ounces", synonyms: ["10 lb 13 oz", "10 pounds and 13 ounces", "10 13"]),
        .lb10oz14: DisplayRepresentation(title: "10 pounds 14 ounces", synonyms: ["10 lb 14 oz", "10 pounds and 14 ounces", "10 14"]),
        .lb10oz15: DisplayRepresentation(title: "10 pounds 15 ounces", synonyms: ["10 lb 15 oz", "10 pounds and 15 ounces", "10 15"]),
        .lb11oz0: DisplayRepresentation(title: "11 pounds", synonyms: ["11 lb", "11 pounds 0 ounces", "11 pounds even"]),
        .lb11oz1: DisplayRepresentation(title: "11 pounds 1 ounce", synonyms: ["11 lb 1 oz", "11 pounds and 1 ounce", "11 1"]),
        .lb11oz2: DisplayRepresentation(title: "11 pounds 2 ounces", synonyms: ["11 lb 2 oz", "11 pounds and 2 ounces", "11 2"]),
        .lb11oz3: DisplayRepresentation(title: "11 pounds 3 ounces", synonyms: ["11 lb 3 oz", "11 pounds and 3 ounces", "11 3"]),
        .lb11oz4: DisplayRepresentation(title: "11 pounds 4 ounces", synonyms: ["11 lb 4 oz", "11 pounds and 4 ounces", "11 4"]),
        .lb11oz5: DisplayRepresentation(title: "11 pounds 5 ounces", synonyms: ["11 lb 5 oz", "11 pounds and 5 ounces", "11 5"]),
        .lb11oz6: DisplayRepresentation(title: "11 pounds 6 ounces", synonyms: ["11 lb 6 oz", "11 pounds and 6 ounces", "11 6"]),
        .lb11oz7: DisplayRepresentation(title: "11 pounds 7 ounces", synonyms: ["11 lb 7 oz", "11 pounds and 7 ounces", "11 7"]),
        .lb11oz8: DisplayRepresentation(title: "11 pounds 8 ounces", synonyms: ["11 lb 8 oz", "11 pounds and 8 ounces", "11 8"]),
        .lb11oz9: DisplayRepresentation(title: "11 pounds 9 ounces", synonyms: ["11 lb 9 oz", "11 pounds and 9 ounces", "11 9"]),
        .lb11oz10: DisplayRepresentation(title: "11 pounds 10 ounces", synonyms: ["11 lb 10 oz", "11 pounds and 10 ounces", "11 10"]),
        .lb11oz11: DisplayRepresentation(title: "11 pounds 11 ounces", synonyms: ["11 lb 11 oz", "11 pounds and 11 ounces", "11 11"]),
        .lb11oz12: DisplayRepresentation(title: "11 pounds 12 ounces", synonyms: ["11 lb 12 oz", "11 pounds and 12 ounces", "11 12"]),
        .lb11oz13: DisplayRepresentation(title: "11 pounds 13 ounces", synonyms: ["11 lb 13 oz", "11 pounds and 13 ounces", "11 13"]),
        .lb11oz14: DisplayRepresentation(title: "11 pounds 14 ounces", synonyms: ["11 lb 14 oz", "11 pounds and 14 ounces", "11 14"]),
        .lb11oz15: DisplayRepresentation(title: "11 pounds 15 ounces", synonyms: ["11 lb 15 oz", "11 pounds and 15 ounces", "11 15"]),
        .lb12oz0: DisplayRepresentation(title: "12 pounds", synonyms: ["12 lb", "12 pounds 0 ounces", "12 pounds even"]),
        .lb12oz1: DisplayRepresentation(title: "12 pounds 1 ounce", synonyms: ["12 lb 1 oz", "12 pounds and 1 ounce", "12 1"]),
        .lb12oz2: DisplayRepresentation(title: "12 pounds 2 ounces", synonyms: ["12 lb 2 oz", "12 pounds and 2 ounces", "12 2"]),
        .lb12oz3: DisplayRepresentation(title: "12 pounds 3 ounces", synonyms: ["12 lb 3 oz", "12 pounds and 3 ounces", "12 3"]),
        .lb12oz4: DisplayRepresentation(title: "12 pounds 4 ounces", synonyms: ["12 lb 4 oz", "12 pounds and 4 ounces", "12 4"]),
        .lb12oz5: DisplayRepresentation(title: "12 pounds 5 ounces", synonyms: ["12 lb 5 oz", "12 pounds and 5 ounces", "12 5"]),
        .lb12oz6: DisplayRepresentation(title: "12 pounds 6 ounces", synonyms: ["12 lb 6 oz", "12 pounds and 6 ounces", "12 6"]),
        .lb12oz7: DisplayRepresentation(title: "12 pounds 7 ounces", synonyms: ["12 lb 7 oz", "12 pounds and 7 ounces", "12 7"]),
        .lb12oz8: DisplayRepresentation(title: "12 pounds 8 ounces", synonyms: ["12 lb 8 oz", "12 pounds and 8 ounces", "12 8"]),
        .lb12oz9: DisplayRepresentation(title: "12 pounds 9 ounces", synonyms: ["12 lb 9 oz", "12 pounds and 9 ounces", "12 9"]),
        .lb12oz10: DisplayRepresentation(title: "12 pounds 10 ounces", synonyms: ["12 lb 10 oz", "12 pounds and 10 ounces", "12 10"]),
        .lb12oz11: DisplayRepresentation(title: "12 pounds 11 ounces", synonyms: ["12 lb 11 oz", "12 pounds and 11 ounces", "12 11"]),
        .lb12oz12: DisplayRepresentation(title: "12 pounds 12 ounces", synonyms: ["12 lb 12 oz", "12 pounds and 12 ounces", "12 12"]),
        .lb12oz13: DisplayRepresentation(title: "12 pounds 13 ounces", synonyms: ["12 lb 13 oz", "12 pounds and 13 ounces", "12 13"]),
        .lb12oz14: DisplayRepresentation(title: "12 pounds 14 ounces", synonyms: ["12 lb 14 oz", "12 pounds and 14 ounces", "12 14"]),
        .lb12oz15: DisplayRepresentation(title: "12 pounds 15 ounces", synonyms: ["12 lb 15 oz", "12 pounds and 15 ounces", "12 15"]),
        .lb13oz0: DisplayRepresentation(title: "13 pounds", synonyms: ["13 lb", "13 pounds 0 ounces", "13 pounds even"]),
        .lb13oz1: DisplayRepresentation(title: "13 pounds 1 ounce", synonyms: ["13 lb 1 oz", "13 pounds and 1 ounce", "13 1"]),
        .lb13oz2: DisplayRepresentation(title: "13 pounds 2 ounces", synonyms: ["13 lb 2 oz", "13 pounds and 2 ounces", "13 2"]),
        .lb13oz3: DisplayRepresentation(title: "13 pounds 3 ounces", synonyms: ["13 lb 3 oz", "13 pounds and 3 ounces", "13 3"]),
        .lb13oz4: DisplayRepresentation(title: "13 pounds 4 ounces", synonyms: ["13 lb 4 oz", "13 pounds and 4 ounces", "13 4"]),
        .lb13oz5: DisplayRepresentation(title: "13 pounds 5 ounces", synonyms: ["13 lb 5 oz", "13 pounds and 5 ounces", "13 5"]),
        .lb13oz6: DisplayRepresentation(title: "13 pounds 6 ounces", synonyms: ["13 lb 6 oz", "13 pounds and 6 ounces", "13 6"]),
        .lb13oz7: DisplayRepresentation(title: "13 pounds 7 ounces", synonyms: ["13 lb 7 oz", "13 pounds and 7 ounces", "13 7"]),
        .lb13oz8: DisplayRepresentation(title: "13 pounds 8 ounces", synonyms: ["13 lb 8 oz", "13 pounds and 8 ounces", "13 8"]),
        .lb13oz9: DisplayRepresentation(title: "13 pounds 9 ounces", synonyms: ["13 lb 9 oz", "13 pounds and 9 ounces", "13 9"]),
        .lb13oz10: DisplayRepresentation(title: "13 pounds 10 ounces", synonyms: ["13 lb 10 oz", "13 pounds and 10 ounces", "13 10"]),
        .lb13oz11: DisplayRepresentation(title: "13 pounds 11 ounces", synonyms: ["13 lb 11 oz", "13 pounds and 11 ounces", "13 11"]),
        .lb13oz12: DisplayRepresentation(title: "13 pounds 12 ounces", synonyms: ["13 lb 12 oz", "13 pounds and 12 ounces", "13 12"]),
        .lb13oz13: DisplayRepresentation(title: "13 pounds 13 ounces", synonyms: ["13 lb 13 oz", "13 pounds and 13 ounces", "13 13"]),
        .lb13oz14: DisplayRepresentation(title: "13 pounds 14 ounces", synonyms: ["13 lb 14 oz", "13 pounds and 14 ounces", "13 14"]),
        .lb13oz15: DisplayRepresentation(title: "13 pounds 15 ounces", synonyms: ["13 lb 15 oz", "13 pounds and 15 ounces", "13 15"]),
        .lb14oz0: DisplayRepresentation(title: "14 pounds", synonyms: ["14 lb", "14 pounds 0 ounces", "14 pounds even"]),
        .lb14oz1: DisplayRepresentation(title: "14 pounds 1 ounce", synonyms: ["14 lb 1 oz", "14 pounds and 1 ounce", "14 1"]),
        .lb14oz2: DisplayRepresentation(title: "14 pounds 2 ounces", synonyms: ["14 lb 2 oz", "14 pounds and 2 ounces", "14 2"]),
        .lb14oz3: DisplayRepresentation(title: "14 pounds 3 ounces", synonyms: ["14 lb 3 oz", "14 pounds and 3 ounces", "14 3"]),
        .lb14oz4: DisplayRepresentation(title: "14 pounds 4 ounces", synonyms: ["14 lb 4 oz", "14 pounds and 4 ounces", "14 4"]),
        .lb14oz5: DisplayRepresentation(title: "14 pounds 5 ounces", synonyms: ["14 lb 5 oz", "14 pounds and 5 ounces", "14 5"]),
        .lb14oz6: DisplayRepresentation(title: "14 pounds 6 ounces", synonyms: ["14 lb 6 oz", "14 pounds and 6 ounces", "14 6"]),
        .lb14oz7: DisplayRepresentation(title: "14 pounds 7 ounces", synonyms: ["14 lb 7 oz", "14 pounds and 7 ounces", "14 7"]),
        .lb14oz8: DisplayRepresentation(title: "14 pounds 8 ounces", synonyms: ["14 lb 8 oz", "14 pounds and 8 ounces", "14 8"]),
        .lb14oz9: DisplayRepresentation(title: "14 pounds 9 ounces", synonyms: ["14 lb 9 oz", "14 pounds and 9 ounces", "14 9"]),
        .lb14oz10: DisplayRepresentation(title: "14 pounds 10 ounces", synonyms: ["14 lb 10 oz", "14 pounds and 10 ounces", "14 10"]),
        .lb14oz11: DisplayRepresentation(title: "14 pounds 11 ounces", synonyms: ["14 lb 11 oz", "14 pounds and 11 ounces", "14 11"]),
        .lb14oz12: DisplayRepresentation(title: "14 pounds 12 ounces", synonyms: ["14 lb 12 oz", "14 pounds and 12 ounces", "14 12"]),
        .lb14oz13: DisplayRepresentation(title: "14 pounds 13 ounces", synonyms: ["14 lb 13 oz", "14 pounds and 13 ounces", "14 13"]),
        .lb14oz14: DisplayRepresentation(title: "14 pounds 14 ounces", synonyms: ["14 lb 14 oz", "14 pounds and 14 ounces", "14 14"]),
        .lb14oz15: DisplayRepresentation(title: "14 pounds 15 ounces", synonyms: ["14 lb 15 oz", "14 pounds and 15 ounces", "14 15"]),
        .lb15oz0: DisplayRepresentation(title: "15 pounds", synonyms: ["15 lb", "15 pounds 0 ounces", "15 pounds even"]),
        .lb15oz1: DisplayRepresentation(title: "15 pounds 1 ounce", synonyms: ["15 lb 1 oz", "15 pounds and 1 ounce", "15 1"]),
        .lb15oz2: DisplayRepresentation(title: "15 pounds 2 ounces", synonyms: ["15 lb 2 oz", "15 pounds and 2 ounces", "15 2"]),
        .lb15oz3: DisplayRepresentation(title: "15 pounds 3 ounces", synonyms: ["15 lb 3 oz", "15 pounds and 3 ounces", "15 3"]),
        .lb15oz4: DisplayRepresentation(title: "15 pounds 4 ounces", synonyms: ["15 lb 4 oz", "15 pounds and 4 ounces", "15 4"]),
        .lb15oz5: DisplayRepresentation(title: "15 pounds 5 ounces", synonyms: ["15 lb 5 oz", "15 pounds and 5 ounces", "15 5"]),
        .lb15oz6: DisplayRepresentation(title: "15 pounds 6 ounces", synonyms: ["15 lb 6 oz", "15 pounds and 6 ounces", "15 6"]),
        .lb15oz7: DisplayRepresentation(title: "15 pounds 7 ounces", synonyms: ["15 lb 7 oz", "15 pounds and 7 ounces", "15 7"]),
        .lb15oz8: DisplayRepresentation(title: "15 pounds 8 ounces", synonyms: ["15 lb 8 oz", "15 pounds and 8 ounces", "15 8"]),
        .lb15oz9: DisplayRepresentation(title: "15 pounds 9 ounces", synonyms: ["15 lb 9 oz", "15 pounds and 9 ounces", "15 9"]),
        .lb15oz10: DisplayRepresentation(title: "15 pounds 10 ounces", synonyms: ["15 lb 10 oz", "15 pounds and 10 ounces", "15 10"]),
        .lb15oz11: DisplayRepresentation(title: "15 pounds 11 ounces", synonyms: ["15 lb 11 oz", "15 pounds and 11 ounces", "15 11"]),
        .lb15oz12: DisplayRepresentation(title: "15 pounds 12 ounces", synonyms: ["15 lb 12 oz", "15 pounds and 12 ounces", "15 12"]),
        .lb15oz13: DisplayRepresentation(title: "15 pounds 13 ounces", synonyms: ["15 lb 13 oz", "15 pounds and 13 ounces", "15 13"]),
        .lb15oz14: DisplayRepresentation(title: "15 pounds 14 ounces", synonyms: ["15 lb 14 oz", "15 pounds and 14 ounces", "15 14"]),
        .lb15oz15: DisplayRepresentation(title: "15 pounds 15 ounces", synonyms: ["15 lb 15 oz", "15 pounds and 15 ounces", "15 15"]),
    ]

    // MARK: Value

    var grams: Double {
        let parts = rawValue.dropFirst(2).split(separator: "o")
        let pounds = Double(parts.first ?? "0") ?? 0
        let ounces = Double(parts.last?.dropFirst(1) ?? "0") ?? 0
        return (pounds * 16 + ounces) * Measure.gramsPerOunce
    }
}
