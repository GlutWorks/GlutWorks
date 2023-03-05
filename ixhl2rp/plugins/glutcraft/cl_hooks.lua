net.Receive( "glutCraftRedraw", function(_, _)
    print("drawing")
    net.ReadEntity():Draw()
end)

