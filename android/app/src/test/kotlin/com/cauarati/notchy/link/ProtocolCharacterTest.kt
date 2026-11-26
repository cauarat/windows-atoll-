package com.cauarati.notchy.link

import com.cauarati.notchy.ReferenceFiles
import com.cauarati.notchy.mochi.MochiAccessory
import com.cauarati.notchy.mochi.MochiCharacter
import com.cauarati.notchy.mochi.MochiEye
import com.cauarati.notchy.mochi.MochiFestive
import com.cauarati.notchy.mochi.MochiShape
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Cap `character`: each session says which Mochi its pill wears on the computer (the Mac's PhoneLinkHub). */
class ProtocolCharacterTest {
    private fun session(character: String) = (Wire.decodeServer(
        """{"type":"sessions","sessions":[{"pillId":"integration_claude","agent":"Claude Code","state":"working","statusText":"",""" +
            """"stepIndex":0,"stepCount":0,"updatedAt":1$character}]}""",
    ) as ServerMsg.Sessions).sessions.single()

    @Test fun theHelloAsksForCharacters() {
        assertTrue(Protocol.CAP_CHARACTER in Protocol.CAPABILITIES)
        val o = JSONObject(Wire.encode(ClientMsg.Hello(1, "T".repeat(20), "Phone", Protocol.CAPABILITIES)))
        assertTrue(o.getJSONArray("caps").toString().contains("\"character\""))
    }

    @Test fun theMacsKeysAreTheOnesRead() {
        // PhoneLinkProtocol.characterKeys on the Mac.
        val mac = ReferenceFiles.read("NotchBuddy/Sources/App/PhoneLink/PhoneLinkProtocol.swift")
        val keys = Regex("""characterKeys: Set<String> = \[([^\]]*)\]""").find(mac)!!.groupValues[1]
            .split(",").map { it.trim().trim('"') }.toSet()
        assertEquals(setOf("accessory", "eye", "shape", "festive"), keys)
    }

    @Test fun aSessionCarriesItsCharacter() {
        val s = session(""","character":{"accessory":"catEars","eye":"shades","shape":"heart","festive":"santaHat.starEye.-.lights"}""")
        assertEquals(
            MochiCharacter(MochiAccessory.CAT_EARS, MochiEye.SHADES, MochiShape.HEART, MochiFestive("santaHat", "starEye", null, "lights")),
            s.character,
        )
    }

    @Test fun noCharacterIsClassic() {
        assertEquals(MochiCharacter.CLASSIC, session("").character)
        assertEquals(MochiCharacter.CLASSIC, session(""","character":{}""").character)
        assertEquals(MochiCharacter.CLASSIC, session(""","character":"crown"""").character)
    }

    @Test fun whatThisBuildDoesNotKnowIsLeftOff() {
        val s = session(""","character":{"accessory":"jetpack","eye":"glossy","shape":"${"x".repeat(80)}","festive":"-.-.-.-","extra":"x"}""")
        assertEquals(MochiCharacter(eye = MochiEye.GLOSSY), s.character)
    }
}
