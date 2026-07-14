// FarmNerdOS default Plasma panel — applied on first login via the
// org.farmnerdos.seedling look-and-feel package.
// Standard bottom panel; Kickoff uses the FarmNerdOS circuit-tree icon.
var panel = new Panel
panel.location = "bottom"
panel.height = Math.round(gridUnit * 2.5)

var kickoff = panel.addWidget("org.kde.plasma.kickoff")
kickoff.currentConfigGroup = ["General"]
kickoff.writeConfig("icon", "farmnerdos")

panel.addWidget("org.kde.plasma.icontasks")
panel.addWidget("org.kde.plasma.marginsseparator")
panel.addWidget("org.kde.plasma.systemtray")
panel.addWidget("org.kde.plasma.digitalclock")
panel.addWidget("org.kde.plasma.showdesktop")
