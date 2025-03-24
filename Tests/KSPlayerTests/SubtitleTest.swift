import Foundation
@testable import KSPlayer
import Testing

class SubtitleTest {
    @Test
    func testSrt() {
        let string = """
        1
        00:00:00,050 --> 00:00:11,000
        <font color="#4096d1">本字幕仅供学习交流，严禁用于商业用途</font>

        2
        00:00:13,000 --> 00:00:18,000
        <font color=#4096d1>-=破烂熊字幕组=-
        翻译:风铃
        校对&时间轴:小白</font>

        3
        00:01:00,840 --> 00:01:02,435
        你现在必须走了吗?

        4
        00:01:02,680 --> 00:01:04,318
        我说过我会去找他的

        5
        00:01:07,194 --> 00:01:08,239
        - 很多事情我们都说过
        - 我承诺过他

        907
        00:59:47,520 --> 00:59:49,720
        有两个人在我们镇上
        There were two men in my hometown

        908
        00:59:51,370 --> 00:59:55,170
        被判4F不合格，他们就自杀了，因为不能服役
        Declared 4-F unfit, they killed themselves cause they couldn't serve.

        909
        00:59:55,750 --> 00:59:58,360
        注：4-F，二战服役有关的物理，心理，或道德标准。
        https://en.wikipedia.org/wiki/Selective_Service_System

         http://www.apd.army.mil/pdffiles/r40_501.pdf

        910
        00:59:59,220 --> 01:00:01,140
        为何？我在国防工厂有份工作
        Why, I had a job in a defense plant.

        """
        let scanner = Scanner(string: string)
        let parse = SrtParse()
        #expect(parse.canParse(scanner: scanner))
        let parts = parse.parse(scanner: scanner) as! [SubtitlePart]
        #expect(parts.count == 9)
        #expect(parts[8].end == 3601.14)
    }

    @Test
    func testSrt2() async {
        let string = """
        1
        00:00:06,886 --> 00:00:08,569
        嘿
        <font size="8px">Hey.</font>

        2
        00:00:09,419 --> 00:00:10,569
        早上好
        <font color="#4096d1">本字幕仅供学习交流，严禁用于商业用途</font>

        """
        let scanner = Scanner(string: string)
        let parse = SrtParse()
        #expect(parse.canParse(scanner: scanner))
        let parts = parse.parse(scanner: scanner) as! [SubtitlePart]
        #expect(parts.count == 2)
        #expect(parts[0].text?.string.contains("<") == false)
        #expect(parts[1].text?.string.contains("<") == false)
    }

    @Test
    func testSrt3() async {
        let string = """
        115
        00:11:10,810 --> 00:11:13,543
        如果我杀了他，她会从悬崖上跳下去。
        <font face="sans-serif" size="71">If I kill him, she'll throw
        herself off a cliff.</font>

        116
        00:11:13,633 --> 00:11:16,005
        当拉尔！我需要你在这里！你在哪里？
        <font face="sans-serif" size="71"><i>Danglars! I need you here!
        Where are you?</i></font>

        """
        let scanner = Scanner(string: string)
        let parse = SrtParse()
        #expect(parse.canParse(scanner: scanner))
        let parts = parse.parse(scanner: scanner) as! [SubtitlePart]
        #expect(parts.count == 2)
        #expect(parts[0].text?.string.contains("<") == false)
        #expect(parts[1].text?.string.contains("<") == false)
    }

    @Test
    func testVtt() {
        let string = """
        WEBVTT
        1
        00:00:00,050 --> 00:00:11,000
        <font color="#4096d1">本字幕仅供学习交流，严禁用于商业用途</font>

        2
        00:00:13,000 --> 00:00:18,000
        <font color=#4096d1>-=破烂熊字幕组=-
        翻译:风铃
        校对&时间轴:小白</font>

        3
        00:01:00,840 --> 00:01:02,435
        你现在必须走了吗?

        4
        00:01:02,680 --> 00:01:04,318
        我说过我会去找他的

        5
        00:01:07,194 --> 00:01:08,239
        - 很多事情我们都说过
        - 我承诺过他

        6
        00:01:08,280 --> 00:01:10,661
        我希望你明白

        7
        00:01:12,814 --> 00:01:14,702
        等等! 你是不可能活着回来的!

        """
        let scanner = Scanner(string: string)
        let parse = VTTParse()
        #expect(parse.canParse(scanner: scanner))
        let parts = parse.parse(scanner: scanner) as! [SubtitlePart]
        #expect(parts.count == 7)
    }

    @Test
    func testVtt2() {
        let string = """
        WEBVTT
        Kind: captions
        Language: en

        00:00:13.240 --> 00:00:15.800
        A few years ago,
        I broke into my own house.

        00:00:16.880 --> 00:00:18.096
        I had just driven home,

        00:00:18.120 --> 00:00:20.656
        it was around midnight
        in the dead of Montreal winter,

        """
        let scanner = Scanner(string: string)
        let parse = VTTParse()
        #expect(parse.canParse(scanner: scanner))
        let parts = parse.parse(scanner: scanner) as! [SubtitlePart]
        #expect(parts.count == 3)
    }
}
