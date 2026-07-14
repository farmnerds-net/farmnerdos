/* FarmNerdOS installer slideshow — Seedling v0.1 */
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        interval: 12000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0C120C"
            Text {
                anchors.centerIn: parent
                width: parent.width * 0.8
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "#5CDB3C"
                font.pixelSize: 26
                text: "Planting FarmNerdOS…\n\nDark mode by default. CachyOS kernel under the hood.\ngrow smart. farm nerdy."
            }
        }
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0C120C"
            Text {
                anchors.centerIn: parent
                width: parent.width * 0.8
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "#DCE8D8"
                font.pixelSize: 22
                text: "Seedling is an alpha.\nExpect some weeds — report them on GitHub\nso the next season grows stronger."
            }
        }
    }
}
