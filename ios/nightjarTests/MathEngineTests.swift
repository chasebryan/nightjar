import XCTest
@testable import nightjar_hack

/// Her arithmetic: exact answers for messages that
/// are mathematics, silence for everything else.
final class MathEngineTests: XCTestCase {

    func testArithmeticAndPrecedence() {
        XCTAssertEqual(MathEngine.answer("what is 47 * 89"),
                       "4183")
        XCTAssertEqual(MathEngine.answer("2 + 3 * 4"), "14")
        XCTAssertEqual(MathEngine.answer("(2 + 3) * 4"), "20")
        XCTAssertEqual(MathEngine.answer("2^10"), "1024")
        XCTAssertEqual(MathEngine.answer("10 / 4"), "2.5")
        XCTAssertEqual(MathEngine.answer("what is -3 + 1"),
                       "-2")
        XCTAssertEqual(MathEngine.answer("2^-2"), "0.25")
    }

    func testFunctionsAndConstants() {
        XCTAssertEqual(MathEngine.answer("sqrt(144)"), "12")
        XCTAssertEqual(MathEngine.answer("log(1000)"), "3")
        XCTAssertEqual(MathEngine.answer("5!"), "120")
        XCTAssertEqual(MathEngine.answer("0!"), "1")
        XCTAssertEqual(MathEngine.answer("abs(-7)"), "7")
        // Degrees, the way people ask.
        XCTAssertEqual(MathEngine.answer("sin(30)"), "0.5")
        // Pi in the question: radians.
        XCTAssertEqual(MathEngine.answer("sin(pi / 2)"), "1")
    }

    func testPercentages() {
        XCTAssertEqual(MathEngine.answer("15% of 240"), "36")
        XCTAssertEqual(MathEngine.answer("what is 15% of 240"),
                       "36")
    }

    func testEquations() {
        XCTAssertEqual(MathEngine.answer("solve 2x + 3 = 7"),
                       "x = 2")
        XCTAssertEqual(MathEngine.answer("x + 5 = 12"),
                       "x = 7")
        XCTAssertEqual(MathEngine.answer("x^2 - 5x + 6 = 0"),
                       "x = 3 or x = 2")
        XCTAssertEqual(MathEngine.answer("x^2 + 1 = 0"),
                       "No real solution.")
    }

    func testProseIsNotMathematics() {
        XCTAssertNil(MathEngine.answer("what is the serve port"))
        XCTAssertNil(MathEngine.answer("call me at 5"))
        XCTAssertNil(MathEngine.answer("2 fast 2 furious"))
        XCTAssertNil(MathEngine.answer("room 101"))
        XCTAssertNil(MathEngine.answer("how many neighbors"))
        XCTAssertNil(MathEngine.answer("sweep the wire"))
        XCTAssertNil(MathEngine.answer(""))
    }

    func testImpossibleIsNotAnswered() {
        XCTAssertNil(MathEngine.answer("what is 1 / 0"))
        XCTAssertNil(MathEngine.answer("sqrt(-4)"))
        XCTAssertNil(MathEngine.answer("200!"))
    }
}
