import SwiftUI
import SpriteKit

struct DefenseGameView: View {
    @EnvironmentObject private var guardian: GuardianManager
    @State private var scene = DefenseScene(size: CGSize(width: 800, height: 600))
    
    var body: some View {
        VStack {
            Text("Whisper Defense: Protect the Core")
                .font(.title)
                .foregroundColor(.cyan)
                .neonGlow()
            
            SpriteView(scene: scene, options: [.allowsTransparency])
                .frame(width: 800, height: 600)
                .background(Color.black)
                .cornerRadius(15)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.purple, lineWidth: 3)
                )
            
            HStack {
                Button("Deploy Hero (Add Block)") {
                    guardian.authenticate {
                        // In a real app, this would open a block editor
                        // For now, it adds a tower to the scene
                        scene.addTower()
                    }
                }
                .buttonStyle(NeonButtonStyle())
                
                Text("Wave: \(scene.currentWave) | Core Health: \(scene.coreHealth)%")
                    .foregroundColor(.green)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding()
        .onAppear {
            scene.guardian = guardian
            scene.startWaves()
        }
    }
}

// SpriteKit Scene — Core Defense Logic
class DefenseScene: SKScene {
    weak var guardian: GuardianManager?
    var coreHealth = 100
    var currentWave = 1
    
    private var coreNode: SKShapeNode!
    private var towers: [SKNode] = []
    
    override func didMove(to view: SKView) {
        backgroundColor = .black
        
        // Central Core (pulsing shield)
        coreNode = SKShapeNode(circleOfRadius: 50)
        coreNode.position = CGPoint(x: size.width/2, y: size.height/2)
        coreNode.fillColor = .cyan
        coreNode.strokeColor = .purple
        coreNode.glowWidth = 10
        addChild(coreNode)
        
        let pulse = SKAction.sequence([
            .scale(to: 1.2, duration: 1),
            .scale(to: 1.0, duration: 1)
        ])
        coreNode.run(.repeatForever(pulse))
    }
    
    func startWaves() {
        // Auto-spawn monsters over time
        run(SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 10), // Wave interval
            SKAction.run { self.spawnWave() }
        ])))
    }
    
    func spawnWave() {
        currentWave += 1
        let monsterCount = currentWave * 2
        
        for _ in 0..<monsterCount {
            let monster = SKShapeNode(rectOf: CGSize(width: 30, height: 30))
            monster.fillColor = .red
            monster.position = randomEdgePosition()
            addChild(monster)
            
            // Path to core
            let move = SKAction.move(to: CGPoint(x: size.width/2, y: size.height/2), duration: 10)
            let damage = SKAction.run {
                self.coreHealth -= 5
                self.guardian?.whisperAlert("Core damage taken!")
            }
            monster.run(SKAction.sequence([move, damage, .removeFromParent()]))
        }
    }
    
    func addTower() {
        // Simple tower placement
        let tower = SKShapeNode(circleOfRadius: 20)
        tower.fillColor = .green
        // Random position near center but not on it
        tower.position = CGPoint(
            x: size.width/2 + CGFloat.random(in: -200...200),
            y: size.height/2 + CGFloat.random(in: -200...200)
        )
        
        // Auto-fire at nearby monsters
        let fire = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 1),
            SKAction.run {
                // Find nearest monster
                if let monster = self.children.first(where: { ($0 as? SKShapeNode)?.fillColor == .red }) {
                    monster.removeFromParent()
                }
            }
        ]))
        tower.run(fire)
        
        addChild(tower)
        towers.append(tower)
    }
    
    private func randomEdgePosition() -> CGPoint {
        let side = Int.random(in: 0..<4)
        switch side {
        case 0: return CGPoint(x: CGFloat.random(in: 0...size.width), y: 0)
        case 1: return CGPoint(x: size.width, y: CGFloat.random(in: 0...size.height))
        case 2: return CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height)
        default: return CGPoint(x: 0, y: CGFloat.random(in: 0...size.height))
        }
    }
}
