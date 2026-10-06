class Advancements{
    static run(){
        Display.clear();
        Display.addSimpleChild("h2","Advancements(Work in Progress):")
        let character = World.getAvatarCharacter();
        for(let advancementType in AdvancementType.descriptors){
            let descriptor=AdvancementType.descriptors[advancementType];
            let currentLevel = character.getAdvancement(advancementType);
            Display.addButton(`${descriptor.getName()} (Current: ${currentLevel}, Cost: ${descriptor.getCost(currentLevel)})`, ()=>{
                Advancements.showDetail(advancementType);                
            });
            Display.addSimpleChild("br");
        }
        Display.addButton("Go Back", Neutral.run)
    }
    static showDetail(advancementType){
        AdvancementDetails.run(advancementType);
    }
}